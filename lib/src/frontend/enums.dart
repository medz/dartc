import '../ast.dart';
import '../source.dart';

// Enum classes carry compiler-owned members whose names cannot be written in
// source, so user declarations and arguments cannot collide with or forge them.
const String enumIndexField = 'index';
const String enumNameField = '#name';
const String enumIndexParameter = '#enumIndex';
const String enumNameParameter = '#enumName';

Never _enumError(SourceProgram program, int token, String message) {
  sourceError(program, program.tokens[token], message);
}

AstExpression _enumName(String name, int token) => AstExpression(
  astName,
  name,
  const <AstExpression>[],
  const <AstType>[],
  token,
);

AstExpression _enumLiteral(int kind, String text, int token) => AstExpression(
  kind,
  text,
  const <AstExpression>[],
  const <AstType>[],
  token,
);

AstExpression _enumNamedArgument(String name, AstExpression value, int token) =>
    AstExpression(
      astNamedArgument,
      name,
      <AstExpression>[value],
      const <AstType>[],
      token,
    );

AstType _enumType(String name, int token) =>
    AstType(name, const <AstType>[], token);

AstParameter _enumHiddenParameter(String type, String name, int token) =>
    AstParameter(_enumType(type, token), name, false, token)
      ..kind = astNamedParameter
      ..required = true;

AstVariable _enumFinalField(String type, String name, int token) => AstVariable(
  _enumType(type, token),
  name,
  <AstExpression>[],
  'final',
  token,
);

AstInitializer _enumFieldInitializer(
  String field,
  String parameter,
  int token,
) => AstInitializer(
  astFieldInitializer,
  field,
  _enumName(parameter, token),
  token,
);

AstFunction _enumArrowMember(
  String name,
  String result,
  AstExpression body,
  bool getter,
  int token,
) => AstFunction(
  name,
  _enumType(result, token),
  <AstParameter>[],
  null,
  body,
  false,
  token,
  getter,
);

bool _enumDeclares(AstClass syntax, String name) {
  for (final value in syntax.enumValues) if (value.name == name) return true;
  for (final field in syntax.fields) if (field.name == name) return true;
  for (final field in syntax.staticFields) if (field.name == name) return true;
  for (final method in syntax.methods) if (method.name == name) return true;
  return false;
}

// Rewrites an enum declaration into the class it denotes: a const class with
// `index` and a private name, one static const instance per value and a
// static const `values` list. Generative constructors receive the hidden index
// and name as required named parameters.
void desugarEnum(SourceProgram program, AstClass syntax) {
  final token = syntax.token;
  if (syntax.enumValues.isEmpty)
    _enumError(program, token, 'enum must declare at least one value');
  var enhanced =
      syntax.interfaces.isNotEmpty ||
      syntax.fields.isNotEmpty ||
      syntax.staticFields.isNotEmpty ||
      syntax.constructors.isNotEmpty ||
      syntax.methods.isNotEmpty;
  for (final value in syntax.enumValues)
    if (value.call != null) enhanced = true;
  if (enhanced &&
      !sourceVersionAtLeast(program, program.tokens[token].source, 2, 17))
    _enumError(program, token, 'enhanced enums require language version 2.17');
  for (final reserved in const <String>['index', 'values', 'hashCode', '==']) {
    if (_enumDeclares(syntax, reserved))
      _enumError(program, token, 'enum cannot declare ' + reserved);
  }
  final hasName = _enumDeclares(syntax, 'name');
  final hasToString = _enumDeclares(syntax, 'toString');

  var generative = false;
  for (final constructor in syntax.constructors) {
    if (constructor.factory) continue;
    generative = true;
    // Generative enum constructors are implicitly const.
    if (constructor.body != null)
      _enumError(
        program,
        constructor.token,
        'enum constructors cannot have a body',
      );
    constructor.constant = true;
    final constructorToken = constructor.token;
    if (constructor.initializers.isNotEmpty &&
        constructor.initializers[0].kind == astRedirectInitializer) {
      final call = constructor.initializers[0].expression;
      call.children.add(
        _enumNamedArgument(
          enumIndexParameter,
          _enumName(enumIndexParameter, constructorToken),
          constructorToken,
        ),
      );
      call.children.add(
        _enumNamedArgument(
          enumNameParameter,
          _enumName(enumNameParameter, constructorToken),
          constructorToken,
        ),
      );
    } else {
      constructor.initializers = <AstInitializer>[
        _enumFieldInitializer(
          enumIndexField,
          enumIndexParameter,
          constructorToken,
        ),
        _enumFieldInitializer(
          enumNameField,
          enumNameParameter,
          constructorToken,
        ),
        ...constructor.initializers,
      ];
    }
    constructor.parameters = <AstParameter>[
      ...constructor.parameters,
      _enumHiddenParameter('int', enumIndexParameter, constructorToken),
      _enumHiddenParameter('String', enumNameParameter, constructorToken),
    ];
  }
  if (syntax.constructors.isEmpty) {
    syntax.constructors = <AstFunction>[
      AstFunction(
          syntax.name,
          AstType('', const <AstType>[], token),
          <AstParameter>[
            _enumHiddenParameter('int', enumIndexParameter, token),
            _enumHiddenParameter('String', enumNameParameter, token),
          ],
          null,
          null,
          false,
          token,
          false,
        )
        ..constant = true
        ..initializers = <AstInitializer>[
          _enumFieldInitializer(enumIndexField, enumIndexParameter, token),
          _enumFieldInitializer(enumNameField, enumNameParameter, token),
        ],
    ];
  } else if (!generative) {
    _enumError(program, token, 'enum requires a generative constructor');
  }

  final instances = <AstVariable>[];
  final references = <AstExpression>[];
  for (var i = 0; i < syntax.enumValues.length; i++) {
    final value = syntax.enumValues[i];
    final call =
        value.call ??
        AstExpression(
          astCall,
          astCallIdentifier,
          <AstExpression>[_enumName(syntax.name, value.token)],
          const <AstType>[],
          value.token,
        );
    call.children.add(
      _enumNamedArgument(
        enumIndexParameter,
        _enumLiteral(astInteger, i.toString(), value.token),
        value.token,
      ),
    );
    call.children.add(
      _enumNamedArgument(
        enumNameParameter,
        _enumLiteral(astString, value.name, value.token),
        value.token,
      ),
    );
    instances.add(
      AstVariable(
        _enumType(syntax.name, value.token),
        value.name,
        <AstExpression>[call],
        'const',
        value.token,
      )..metadata = value.metadata,
    );
    references.add(_enumName(value.name, value.token));
  }
  instances.add(
    AstVariable(
      AstType('List', <AstType>[_enumType(syntax.name, token)], token),
      'values',
      <AstExpression>[
        AstExpression(astList, '', references, const <AstType>[], token),
      ],
      'const',
      token,
    ),
  );
  syntax.staticFields = <AstVariable>[...instances, ...syntax.staticFields];
  syntax.fields = <AstVariable>[
    _enumFinalField('int', enumIndexField, token),
    _enumFinalField('String', enumNameField, token),
    ...syntax.fields,
  ];
  if (!hasName)
    syntax.methods.add(
      _enumArrowMember(
        'name',
        'String',
        _enumName(enumNameField, token),
        true,
        token,
      ),
    );
  if (!hasToString)
    syntax.methods.add(
      _enumArrowMember(
        'toString',
        'String',
        AstExpression(
          astBinary,
          '+',
          <AstExpression>[
            _enumLiteral(astString, syntax.name + '.', token),
            _enumName(enumNameField, token),
          ],
          const <AstType>[],
          token,
        ),
        false,
        token,
      ),
    );
}
