import 'package:dartc/ir.dart';
import 'package:test/test.dart';

final _uri = Uri.parse('memory:call-types');

void main() {
  test('unions multiple callers through parameters and returned values', () {
    final model = _dispatch();
    final identity = FunctionTarget(_uri, 'identity', model.face, [model.face]);
    final identityBody = _identity(identity);
    final forward = FunctionTarget(_uri, 'forward', model.face, [model.face]);
    final forwarding = Block(forward.parameterTypes);
    forwarding.finish(
      Return(forwarding.emit(DirectCall(identity, forwarding.parameters))),
    );
    final read = FunctionTarget(_uri, 'read', .integer, [model.face]);
    final reading = Block(read.parameterTypes);
    final returned = reading.emit(DirectCall(forward, reading.parameters));
    reading.finish(
      Return(reading.emit(InstanceCall(model.member, returned, []))),
    );
    final entry = Block();
    for (final type in model.types.take(2)) {
      entry.emit(DirectCall(read, [ObjectConstant(type, {})]));
    }
    entry.emit(
      ObjectHashCode(ObjectConstant(model.types.last, {}), direct: true),
    );
    entry.finish(const Return());
    final root = IrFunction(FunctionTarget(_uri, 'main', .voidType, []), [
      entry,
    ]);
    final program = IrProgram(model.classes, [
      ...model.bodies,
      identityBody,
      IrFunction(forward, [forwarding]),
      IrFunction(read, [reading]),
      root,
    ]);
    final flow = CallTypeFlow(program, [root.target]);
    expect(flow.definitions, containsAll(model.members.take(2)));
    expect(flow.definitions, isNot(contains(model.members.last)));
    expect(flow.allows(returned, model.types[0]), isTrue);
    expect(flow.allows(returned, model.types[1]), isTrue);
    expect(flow.allows(returned, model.types[2]), isFalse);
    expect(program.reachableFrom([root.target]), contains(model.members.last));
  });

  test('new virtual targets propagate returns across unordered blocks', () {
    final model = _dispatch();
    final holder = ClassType(_uri, 'Holder');
    final produce = FunctionTarget(
      _uri,
      'produce',
      model.face,
      [],
      owner: holder,
      kind: .method,
    );
    final producing = Block(produce.parameterTypes)
      ..finish(Return(ObjectConstant(model.types.first, {})));
    final root = FunctionTarget(_uri, 'main', .integer, [holder]);
    final entry = Block(root.parameterTypes);
    final definition = Block(), consumer = Block();
    final returned = definition.emit(
      InstanceCall(produce, entry.parameters.single, []),
    );
    entry.finish(Jump(definition));
    definition.finish(Jump(consumer));
    consumer.finish(
      Return(consumer.emit(InstanceCall(model.member, returned, []))),
    );
    final program = IrProgram(
      [
        ...model.classes,
        IrClass(holder, [], members: [produce]),
      ],
      [
        ...model.bodies,
        IrFunction(produce, [producing]),
        IrFunction(root, [entry, consumer, definition]),
      ],
    );
    final flow = CallTypeFlow(program, [produce], instantiatedTypes: [holder]);
    expect(flow.definitions, {produce});
    expect(flow.extend(unknownCalls: [root]), isTrue);
    expect(flow.definitions, {produce, root, model.members.first});
    expect(flow.allows(returned, model.types.first), isTrue);
    expect(flow.allows(returned, model.types.last), isFalse);
    expect(flow.extend(unknownCalls: [root]), isFalse);
  });

  test('joins loop parameters and recursive returns to a fixed point', () {
    final model = _dispatch();
    final recursive = FunctionTarget(_uri, 'recursive', model.face, [
      model.face,
      .boolean,
    ]);
    final entry = Block(recursive.parameterTypes);
    final done = Block(), again = Block();
    entry.finish(Branch(entry.parameters[1], Jump(done), Jump(again)));
    done.finish(Return(entry.parameters[0]));
    again.finish(
      Return(
        again.emit(
          DirectCall(recursive, [
            ObjectConstant(model.types[1], {}),
            const Constant.boolean(true),
          ]),
        ),
      ),
    );
    final rootEntry = Block([.boolean]);
    final loop = Block([model.face, .boolean]);
    rootEntry.finish(
      Jump(loop, [
        rootEntry.emit(
          DirectCall(recursive, [
            ObjectConstant(model.types[0], {}),
            rootEntry.parameters.single,
          ]),
        ),
        rootEntry.parameters.single,
      ]),
    );
    final exit = Block();
    loop.finish(
      Branch(
        loop.parameters[1],
        Jump(exit),
        Jump(loop, [
          ObjectConstant(model.types[1], {}),
          const Constant.boolean(true),
        ]),
      ),
    );
    exit.finish(
      Return(exit.emit(InstanceCall(model.member, loop.parameters.first, []))),
    );
    final root = IrFunction(
      FunctionTarget(_uri, 'main', .integer, [.boolean]),
      [rootEntry, loop, exit],
    );
    final program = IrProgram(model.classes, [
      ...model.bodies,
      IrFunction(recursive, [entry, done, again]),
      root,
    ]);
    final flow = CallTypeFlow(program, [
      root.target,
    ], instantiatedTypes: model.types);
    expect(flow.definitions, containsAll(model.members.take(2)));
    expect(flow.definitions, isNot(contains(model.members.last)));
  });

  test('unknown callers widen existing functions and add new entry points', () {
    final model = _dispatch();
    final reader = _reader(model);
    final rootEntry = Block();
    rootEntry.finish(
      Return(
        rootEntry.emit(
          DirectCall(reader.target, [ObjectConstant(model.types.first, {})]),
        ),
      ),
    );
    final root = IrFunction(FunctionTarget(_uri, 'main', .integer, []), [
      rootEntry,
    ]);
    final program = IrProgram(model.classes, [...model.bodies, reader, root]);
    final narrow = CallTypeFlow(program, [
      root.target,
    ], instantiatedTypes: model.types);
    expect(narrow.definitions.intersection(model.members.toSet()), {
      model.members.first,
    });
    for (final roots in [
      <FunctionTarget>[],
      [root.target],
    ]) {
      final flow = CallTypeFlow(
        program,
        roots,
        instantiatedTypes: model.types,
        unknownCalls: [reader.target],
      );
      expect(flow.definitions, contains(reader.target));
      expect(flow.definitions, containsAll(model.members));
    }
  });

  test('incremental entries and instances match fresh analysis', () {
    final model = _dispatch();
    final identity = FunctionTarget(_uri, 'identity', model.face, [model.face]);
    final identityBody = _identity(identity);
    final late = FunctionTarget(_uri, 'late', model.face, [model.face]);
    final forwarding = Block(late.parameterTypes);
    forwarding.finish(
      Return(forwarding.emit(DirectCall(identity, forwarding.parameters))),
    );
    final entry = Block();
    final value = entry.emit(
      DirectCall(identity, [ObjectConstant(model.types.first, {})]),
    );
    entry.finish(Return(entry.emit(InstanceCall(model.member, value, []))));
    final root = IrFunction(FunctionTarget(_uri, 'main', .integer, []), [
      entry,
    ]);
    final program = IrProgram(model.classes, [
      ...model.bodies,
      identityBody,
      IrFunction(late, [forwarding]),
      root,
    ]);
    final flow = CallTypeFlow(program, [root.target]);
    final view = flow.definitions;
    expect(view.intersection(model.members.toSet()), {model.members.first});
    expect(flow.allows(value, model.types.last), isFalse);
    expect(() => view.add(late), throwsUnsupportedError);
    expect(flow.extend(unknownCalls: [model.members.first]), isFalse);
    final entries = <FunctionTarget>[], instances = <ClassType>[];
    for (final (calls, types) in [
      ([identity], <ClassType>[]),
      (<FunctionTarget>[], [model.types[1]]),
      ([late], <ClassType>[]),
      (<FunctionTarget>[], [model.types[2]]),
    ]) {
      entries.addAll(calls);
      instances.addAll(types);
      expect(
        flow.extend(unknownCalls: calls, instantiatedTypes: types),
        isTrue,
      );
      final fresh = CallTypeFlow(
        program,
        [root.target],
        unknownCalls: entries,
        instantiatedTypes: instances,
      );
      expect(view, fresh.definitions);
      expect(flow.definitions, same(view));
      for (final receiver in [
        value,
        identityBody.entry.parameters.single,
        forwarding.parameters.single,
      ]) {
        for (final type in model.types) {
          expect(flow.allows(receiver, type), fresh.allows(receiver, type));
        }
      }
      expect(
        flow.extend(unknownCalls: entries, instantiatedTypes: instances),
        isFalse,
      );
    }
    expect(view, containsAll([late, ...model.members]));
    expect(flow.extend(), isFalse);
    final dormant = CallTypeFlow(program, []);
    expect(dormant.extend(instantiatedTypes: [model.types.first]), isTrue);
    expect(dormant.definitions, isEmpty);
    expect(dormant.extend(instantiatedTypes: [model.types.first]), isFalse);
  });

  test('unrelated selectors do not widen dynamic calls', () {
    final model = _dispatch();
    final other = ClassType(_uri, 'OtherSelector');
    final unrelated = FunctionTarget(
      _uri,
      'other',
      .integer,
      [],
      owner: other,
      kind: .method,
    );
    final root = FunctionTarget(_uri, 'main', .dynamicType, [.object]);
    final entry = Block(root.parameterTypes);
    entry.finish(
      Return(
        entry.emit(
          DynamicDispatch(entry.parameters.single, model.member.selector, []),
        ),
      ),
    );
    final program = IrProgram(
      [
        ...model.classes,
        IrClass(other, [], members: [unrelated]),
      ],
      [
        ...model.bodies,
        IrFunction(unrelated, [
          Block(unrelated.parameterTypes)
            ..finish(const Return(Constant.integer(0))),
        ]),
        IrFunction(root, [entry]),
      ],
    );
    final flow = CallTypeFlow(
      program,
      [root],
      instantiatedTypes: [model.types.first],
    );
    final selected = flow.definitions.toSet();
    expect(selected, {root, model.members.first});
    expect(flow.allows(entry.parameters.single, other), isTrue);
    expect(flow.extend(instantiatedTypes: [other]), isTrue);
    expect(flow.definitions, selected);
    expect(flow.extend(instantiatedTypes: [other]), isFalse);
  });

  test('new instances respect call facts and tear-off declaration bounds', () {
    final model = _dispatch();
    final identity = FunctionTarget(_uri, 'identity', model.face, [model.face]);
    for (final bound in [false, true]) {
      final entry = Block();
      final receiver = entry.emit(
        DirectCall(identity, [ObjectConstant(model.types.first, {})]),
      );
      entry.emit(
        bound
            ? BindMethod(model.member, receiver)
            : InstanceCall(model.member, receiver, []),
      );
      entry.finish(const Return());
      final root = IrFunction(FunctionTarget(_uri, 'main', .voidType, []), [
        entry,
      ]);
      final program = IrProgram(model.classes, [
        ...model.bodies,
        _identity(identity),
        root,
      ]);
      final flow = CallTypeFlow(program, [root.target]);
      expect(flow.definitions.intersection(model.members.toSet()), {
        model.members.first,
      });
      expect(flow.allows(receiver, model.types[1]), isFalse);
      expect(flow.extend(instantiatedTypes: [model.types[1]]), isTrue);
      expect(flow.definitions.intersection(model.members.toSet()), {
        model.members.first,
        if (bound) model.members[1],
      });
      expect(flow.allows(receiver, model.types[1]), isFalse);
    }
  });

  test(
    'generic parameters combine actual values without fixing their binder',
    () {
      final model = _dispatch();
      final parameter = TypeParameterType('T')..initializeBound(model.face);
      final identity = FunctionTarget(
        _uri,
        'identity',
        parameter,
        [parameter],
        typeParameters: [parameter],
      );
      final body = _identity(identity);
      final entry = Block();
      for (final type in model.types.take(2)) {
        final value = entry.emit(
          DirectCall(
            identity,
            [ObjectConstant(type, {})],
            typeArguments: [model.face],
          ),
        );
        entry.emit(InstanceCall(model.member, value, []));
      }
      entry.finish(const Return());
      final root = IrFunction(FunctionTarget(_uri, 'main', .voidType, []), [
        entry,
      ]);
      final program = IrProgram(model.classes, [...model.bodies, body, root]);
      final narrow = CallTypeFlow(program, [
        root.target,
      ], instantiatedTypes: model.types);
      expect(
        narrow.definitions.intersection(model.members.toSet()),
        model.members.take(2).toSet(),
      );
      final open = CallTypeFlow(
        program,
        [root.target],
        instantiatedTypes: model.types,
        unknownCalls: [identity],
      );
      expect(open.definitions, containsAll(model.members));
    },
  );

  test('nullable arguments retain both null and non-null alternatives', () {
    final model = _dispatch();
    final identity = FunctionTarget(_uri, 'identity', .object.nullable, [
      .object.nullable,
    ]);
    final body = _identity(identity);
    final entry = Block();
    entry.emit(DirectCall(identity, [const Constant.nullValue()]));
    entry.emit(DirectCall(identity, [ObjectConstant(model.types.first, {})]));
    entry.finish(const Return());
    final root = IrFunction(FunctionTarget(_uri, 'main', .voidType, []), [
      entry,
    ]);
    final flow = CallTypeFlow(
      IrProgram(model.classes, [...model.bodies, body, root]),
      [root.target],
    );
    final value = body.entry.parameters.single;
    expect(flow.allows(value, ValueType.nullClass), isTrue);
    expect(flow.allows(value, model.types.first), isTrue);
    expect(flow.allows(value, model.types.last), isFalse);
  });

  test('a later escaping function widens prior parameters and returns', () {
    final model = _dispatch();
    final identity = FunctionTarget(_uri, 'identity', model.face, [model.face]);
    final escape = FunctionTarget(_uri, 'escape', identity.signature, []);
    final escaping = IrFunction(escape, [
      Block()..finish(Return(FunctionConstant(identity))),
    ]);
    final entry = Block();
    final value = entry.emit(
      DirectCall(identity, [ObjectConstant(model.types.first, {})]),
    );
    final read = entry.emit(InstanceCall(model.member, value, []));
    entry.emit(DirectCall(escape, []));
    entry.finish(Return(read));
    final root = IrFunction(FunctionTarget(_uri, 'main', .integer, []), [
      entry,
    ]);
    final program = IrProgram(model.classes, [
      ...model.bodies,
      _identity(identity),
      escaping,
      root,
    ]);
    final flow = CallTypeFlow(program, [
      root.target,
    ], instantiatedTypes: model.types);
    expect(flow.definitions, containsAll(model.members));
    for (final type in model.types) {
      expect(flow.allows(value, type), isTrue);
    }
  });

  test('function values and lexical captures remain conservative', () {
    final model = _dispatch();
    final reader = _reader(model);
    final root = FunctionTarget(_uri, 'main', .voidType, []);
    final closure = FunctionTarget(
      _uri,
      'closure',
      .integer,
      [],
      kind: .closure,
      enclosing: root,
      sourceOffset: 0,
      captures: [model.face],
    );
    final captured = Block(closure.parameterTypes);
    captured.finish(
      Return(
        captured.emit(InstanceCall(model.member, captured.parameters[1], [])),
      ),
    );
    final entry = Block();
    entry.emit(
      FunctionCall(FunctionConstant(reader.target), [
        ObjectConstant(model.types.first, {}),
      ]),
    );
    entry.emit(MakeClosure(closure, [ObjectConstant(model.types.first, {})]));
    entry.finish(const Return());
    final program = IrProgram(model.classes, [
      ...model.bodies,
      reader,
      IrFunction(root, [entry]),
      IrFunction(closure, [captured]),
    ]);
    final flow = CallTypeFlow(program, [root], instantiatedTypes: model.types);
    expect(
      flow.definitions,
      containsAll([closure, reader.target, ...model.members]),
    );
    expect(flow.allows(captured.parameters[1], model.types.last), isTrue);
  });

  test('native callback entries seed unknown parameter values', () {
    final target = FunctionTarget(_uri, 'callback', .integer, [.integer]);
    final body = _identity(target);
    final callback = NativeCallbackAddress(
      target,
      FunctionType(FfiTypes.int64, [FfiTypes.int64]),
      exceptionalReturn: const Constant.integer(-1),
    );
    final entry = Block()
      ..emit(callback)
      ..finish(const Return());
    final root = IrFunction(FunctionTarget(_uri, 'main', .voidType, []), [
      entry,
    ]);
    final flow = CallTypeFlow(IrProgram([], [body, root]), [root.target]);
    expect(flow.definitions, contains(target));
    expect(
      flow.allows(body.entry.parameters.single, ValueType.integer),
      isTrue,
    );
  });

  test('exception edges keep calls and unknown exception receiver types', () {
    final model = _dispatch();
    final source = FunctionTarget(_uri, 'source', model.face, []);
    final entry = Block();
    final normal = Block([model.face]), caught = Block([.object]);
    final operation = DirectCall(source, []);
    entry.finish(
      Invoke(
        operation,
        onReturn: Jump(normal, [operation]),
        onThrow: Jump(caught, [UnwindValue.exception]),
      ),
    );
    normal.finish(
      Return(
        normal.emit(InstanceCall(model.member, normal.parameters.single, [])),
      ),
    );
    final cast = caught.emit(TypeCast(caught.parameters.single, model.face));
    caught.finish(Return(caught.emit(InstanceCall(model.member, cast, []))));
    final root = IrFunction(FunctionTarget(_uri, 'main', .integer, []), [
      entry,
      normal,
      caught,
    ]);
    final sourceBody = IrFunction(source, [
      Block()..finish(Return(ObjectConstant(model.types.first, {}))),
    ]);
    final program = IrProgram(model.classes, [
      ...model.bodies,
      sourceBody,
      root,
    ]);
    final flow = CallTypeFlow(program, [
      root.target,
    ], instantiatedTypes: model.types);
    expect(flow.definitions, containsAll([source, ...model.members]));
    expect(root.entry.end, same(entry.end));
    expect(caught.instructions.first, same(cast));
  });

  test('virtual forwarding uses the selected implementation defaults', () {
    final model = _dispatch();
    final owner = ClassType(_uri, 'Forwarder');
    final method = FunctionTarget(
      _uri,
      'forward',
      .integer,
      [model.face],
      owner: owner,
      kind: .method,
      optionalPositional: 1,
    );
    final body = Block(method.parameterTypes);
    body.finish(
      Return(body.emit(InstanceCall(model.member, body.parameters[1], []))),
    );
    final main = Block();
    main.finish(
      Return(main.emit(InstanceCall(method, ObjectConstant(owner, {}), []))),
    );
    final root = IrFunction(FunctionTarget(_uri, 'main', .integer, []), [main]);
    final program = IrProgram(
      [
        ...model.classes,
        IrClass(owner, [], members: [method]),
      ],
      [
        ...model.bodies,
        IrFunction(
          method,
          [body],
          defaults: {0: ObjectConstant(model.types[1], {})},
        ),
        root,
      ],
    );
    final flow = CallTypeFlow(program, [
      root.target,
    ], instantiatedTypes: model.types);
    expect(flow.definitions.intersection(model.members.toSet()), {
      model.members[1],
    });
  });

  test('storage and imported return values retain their static bounds', () {
    final model = _dispatch();
    final owner = ClassType(_uri, 'Storage');
    final field = InstanceField(owner, 'value', model.face, isFinal: true);
    final external = FunctionTarget(_uri, 'external', model.face, []);
    for (final imported in [false, true]) {
      final entry = Block();
      final value = imported
          ? entry.emit(DirectCall(external, []))
          : entry.emit(
              LoadField(
                field,
                ObjectConstant(owner, {
                  field: ObjectConstant(model.types.first, {}),
                }),
              ),
            );
      entry.finish(Return(entry.emit(InstanceCall(model.member, value, []))));
      final root = IrFunction(FunctionTarget(_uri, 'main', .integer, []), [
        entry,
      ]);
      final program = IrProgram(
        [
          ...model.classes,
          IrClass(owner, [field]),
        ],
        [...model.bodies, root],
        externals: [IrExternal(external)],
      );
      final flow = CallTypeFlow(program, [
        root.target,
      ], instantiatedTypes: model.types);
      expect(flow.definitions, containsAll(model.members));
    }
  });

  test('constructor arguments flow and redirect tear-offs stay unknown', () {
    final model = _dispatch();
    final owner = ClassType(_uri, 'Container');
    final initialize = FunctionTarget(
      _uri,
      'new',
      .voidType,
      [model.face],
      owner: owner,
      kind: .initializer,
    );
    final redirect = FunctionTarget(
      _uri,
      'redirect',
      owner,
      [model.face],
      owner: owner,
      kind: .factory,
      redirect: initialize,
    );
    final body = Block(initialize.parameterTypes);
    body.emit(InstanceCall(model.member, body.parameters[1], []));
    body.finish(const Return());
    for (final tearOff in [false, true]) {
      final entry = Block();
      if (tearOff) {
        entry.emit(
          FunctionCall(FunctionConstant(redirect), [
            ObjectConstant(model.types.first, {}),
          ]),
        );
      } else {
        entry.emit(
          Construct(initialize, [ObjectConstant(model.types.first, {})]),
        );
      }
      entry.finish(const Return());
      final root = IrFunction(FunctionTarget(_uri, 'main', .voidType, []), [
        entry,
      ]);
      final program = IrProgram(
        [
          ...model.classes,
          IrClass(owner, [], constructors: [initialize, redirect]),
        ],
        [
          ...model.bodies,
          IrFunction(initialize, [body]),
          root,
        ],
      );
      final flow = CallTypeFlow(program, [
        root.target,
      ], instantiatedTypes: model.types);
      expect(flow.definitions, contains(initialize));
      expect(flow.definitions, isNot(contains(redirect)));
      expect(
        flow.definitions.intersection(model.members.toSet()),
        tearOff ? model.members.toSet() : {model.members.first},
      );
    }
  });
}

IrFunction _identity(FunctionTarget target) {
  final entry = Block(target.parameterTypes);
  entry.finish(Return(entry.parameters.single));
  return IrFunction(target, [entry]);
}

IrFunction _reader(_Dispatch model) {
  final target = FunctionTarget(_uri, 'read', .integer, [model.face]);
  final entry = Block(target.parameterTypes);
  entry.finish(
    Return(entry.emit(InstanceCall(model.member, entry.parameters.single, []))),
  );
  return IrFunction(target, [entry]);
}

typedef _Dispatch = ({
  ClassType face,
  FunctionTarget member,
  List<ClassType> types,
  List<FunctionTarget> members,
  List<IrClass> classes,
  List<IrFunction> bodies,
});

_Dispatch _dispatch() {
  final face = ClassType(_uri, 'Face', isAbstract: true);
  final member = FunctionTarget(
    _uri,
    'value',
    .integer,
    [],
    owner: face,
    kind: .method,
    isAbstract: true,
  );
  final types = [
    for (final name in ['First', 'Second', 'Unrelated'])
      ClassType(_uri, name, interfaces: [face]),
  ];
  final members = [
    for (final type in types)
      FunctionTarget(_uri, 'value', .integer, [], owner: type, kind: .method),
  ];
  return (
    face: face,
    member: member,
    types: types,
    members: members,
    classes: [
      IrClass(face, [], members: [member]),
      for (final (i, type) in types.indexed)
        IrClass(type, [], members: [members[i]]),
    ],
    bodies: [
      for (final (i, target) in members.indexed)
        IrFunction(target, [
          Block(target.parameterTypes)..finish(Return(Constant.integer(i))),
        ]),
    ],
  );
}
