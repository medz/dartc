import '../../lib/runtime/contracts.dart';

/// The type descriptor shared by generated code and Dart runtime algorithms.
@TypeStorage(0)
final class TypeInfo(
  final int kind,
  final int shape,
  final bool allowsNull,
  final TypeArguments? parts,
  final FunctionInfo? signature,
  final String className,
) implements Type {
  @Primitive(.typeView)
  external static TypeInfo of(Type value);

  /// Projects onto one nominal declaration without constructing unrelated types.
  @Primitive(.typeProjection)
  external TypeInfo? _asInstanceOf(int shape);

  @override
  bool operator ==(Object other) => equal(this, other);

  @RuntimeEntry(.typeEquals)
  static bool equal(TypeInfo left, Object? other) =>
      other is TypeInfo &&
      left.kind == other.kind &&
      left.shape == other.shape &&
      TypeArguments.equal(left.parts, other.parts);

  @RuntimeEntry(.typeHash)
  @override
  int get hashCode => _mix(_mix(kind, shape), TypeArguments.hash(parts));

  @RuntimeEntry(.typeNullable)
  TypeInfo get nullable {
    if (allowsNull) return this;
    if (kind == TypeKind.never.index) return of(Null);
    return TypeInfo(
      TypeKind.nullable.index,
      0,
      true,
      TypeArguments(this, null),
      null,
      'nullable',
    );
  }

  TypeInfo get _future => TypeInfo(
    TypeKind.nominal.index,
    of(Future).shape,
    false,
    TypeArguments(this, null),
    null,
    'Future',
  );

  @RuntimeEntry(.typeFutureOr)
  TypeInfo get futureOr {
    if (kind == TypeKind.dynamicType.index || kind == TypeKind.voidType.index) {
      return this;
    }
    final base = kind == TypeKind.nullable.index ? parts!.head : this;
    if (base.kind == TypeKind.nominal.index && base.shape == of(Object).shape) {
      return this;
    }
    if (kind == TypeKind.never.index) return _future;
    if (kind == TypeKind.nullType.index) return _future.nullable;
    return TypeInfo(
      TypeKind.futureOr.index,
      0,
      allowsNull,
      TypeArguments(this, null),
      null,
      'futureOr',
    );
  }

  @RuntimeEntry(.typeParameter)
  TypeInfo withBound(TypeInfo bound) =>
      bound.kind == TypeKind.never.index ? bound : this;

  @RuntimeEntry(.typeShift)
  TypeInfo shift(int amount, int cutoff) {
    if (kind == TypeKind.parameter.index) {
      return shape < cutoff
          ? this
          : TypeInfo(kind, shape + amount, false, null, null, className);
    }
    if (parts == null) return this;
    return TypeInfo(
      kind,
      shape,
      allowsNull,
      parts!.shift(amount, cutoff + (signature?.binders ?? 0)),
      signature,
      className,
    );
  }

  @RuntimeEntry(.typeSubtype)
  bool isSubtypeOf(TypeInfo other) => _isSubtype(other, null, null, null);

  bool _isSubtype(
    TypeInfo other,
    _TypeScope? sourceScope,
    _TypeScope? targetScope,
    _BoundCheck? active,
  ) {
    final targetKind = other.kind;
    if (targetKind == TypeKind.dynamicType.index ||
        targetKind == TypeKind.voidType.index ||
        targetKind == TypeKind.nullable.index &&
            other.parts!.head.kind == TypeKind.nominal.index &&
            other.parts!.head.shape == of(Object).shape) {
      return true;
    }
    if (kind == TypeKind.never.index) return true;
    if (kind == TypeKind.dynamicType.index || kind == TypeKind.voidType.index) {
      return false;
    }
    if (kind == TypeKind.nullType.index) return other.allowsNull;
    if (kind == TypeKind.nullable.index || kind == TypeKind.futureOr.index) {
      final child = parts!.head;
      final arm = kind == TypeKind.nullable.index ? of(Null) : child._future;
      return child._isSubtype(other, sourceScope, targetScope, active) &&
          arm._isSubtype(other, sourceScope, targetScope, active);
    }
    if (targetKind == TypeKind.nullable.index ||
        targetKind == TypeKind.futureOr.index) {
      final child = other.parts!.head;
      if (_isSubtype(child, sourceScope, targetScope, active) ||
          targetKind == TypeKind.futureOr.index &&
              _isSubtype(child._future, sourceScope, targetScope, active)) {
        return true;
      }
      return kind == TypeKind.parameter.index &&
          _boundSubtype(other, sourceScope!, targetScope, active);
    }
    if (kind == TypeKind.parameter.index) {
      if (targetKind == TypeKind.parameter.index) {
        final left = sourceScope!.scopeAt(shape);
        final right = targetScope!.scopeAt(other.shape);
        if (identical(left.owner, right.owner) &&
            sourceScope.slot(shape, left) ==
                targetScope.slot(other.shape, right)) {
          return true;
        }
      }
      return _boundSubtype(other, sourceScope!, targetScope, active);
    }
    if (targetKind == TypeKind.parameter.index) return false;
    if (targetKind == TypeKind.nominal.index &&
        other.shape == of(Object).shape) {
      return true;
    }
    if (kind == TypeKind.function.index) {
      return targetKind == TypeKind.function.index
          ? _functionSubtype(other, sourceScope, targetScope, active)
          : targetKind == TypeKind.nominal.index &&
                other.shape == of(Function).shape;
    }
    if (kind == TypeKind.record.index) {
      if (targetKind == TypeKind.record.index) {
        return shape == other.shape &&
            TypeArguments._subtypes(
              parts,
              other.parts,
              sourceScope,
              targetScope,
              active,
            );
      }
      if (targetKind != TypeKind.nominal.index) return false;
      if (other.shape == of(Record).shape) return true;
    } else {
      if (kind != TypeKind.nominal.index ||
          targetKind != TypeKind.nominal.index) {
        return false;
      }
      if (shape == other.shape) {
        return TypeArguments._subtypes(
          parts,
          other.parts,
          sourceScope,
          targetScope,
          active,
        );
      }
    }
    final view = _asInstanceOf(other.shape);
    return view != null &&
        TypeArguments._subtypes(
          view.parts,
          other.parts,
          sourceScope,
          targetScope,
          active,
        );
  }

  bool _boundSubtype(
    TypeInfo other,
    _TypeScope sourceScope,
    _TypeScope? targetScope,
    _BoundCheck? active,
  ) {
    final scope = sourceScope.scopeAt(shape);
    final slot = sourceScope.slot(shape, scope);
    final owner = scope.owner;
    for (var check = active; check != null; check = check.next) {
      if (identical(check.owner, owner) &&
          check.slot == slot &&
          identical(check.scope, targetScope) &&
          check.target == other) {
        return false;
      }
    }
    return TypeArguments.at(owner.bounds, slot)._isSubtype(
      other,
      owner,
      targetScope,
      _BoundCheck(owner, slot, other, targetScope, active),
    );
  }

  bool _functionSubtype(
    TypeInfo other,
    _TypeScope? sourceScope,
    _TypeScope? targetScope,
    _BoundCheck? active,
  ) {
    final a = signature!, b = other.signature!;
    final count = a.binders;
    if (count != b.binders ||
        a.required > b.required ||
        a.positional < b.positional) {
      return false;
    }
    if (count != 0) {
      sourceScope = _TypeScope(count, parts, sourceScope, null);
      // Both signatures bind the same fresh variables with the source's bounds.
      targetScope = _TypeScope(count, null, targetScope, sourceScope);
    }
    for (var i = 0; i < count; i++) {
      final left = TypeArguments.at(parts, i),
          right = TypeArguments.at(other.parts, i);
      if (!left._isSubtype(right, sourceScope, targetScope, active) ||
          !right._isSubtype(left, targetScope, sourceScope, active)) {
        return false;
      }
    }
    if (!TypeArguments.at(parts, count)._isSubtype(
      TypeArguments.at(other.parts, count),
      sourceScope,
      targetScope,
      active,
    )) {
      return false;
    }
    for (var i = 0; i < b.positional; i++) {
      final slot = count + 1 + i;
      if (!TypeArguments.at(other.parts, slot)._isSubtype(
        TypeArguments.at(parts, slot),
        targetScope,
        sourceScope,
        active,
      )) {
        return false;
      }
    }
    for (var name = b.named; name != null; name = name.next) {
      final found = a.find(name.name);
      if (found == null ||
          !TypeArguments.at(other.parts, name.slot)._isSubtype(
            TypeArguments.at(parts, found.slot),
            targetScope,
            sourceScope,
            active,
          )) {
        return false;
      }
    }
    for (var name = a.named; name != null; name = name.next) {
      if (name.required && b.find(name.name)?.required != true) return false;
    }
    return true;
  }

  @override
  String toString() => _text(const []);

  String _text(List<String> variables) {
    final arguments = <TypeInfo>[];
    for (var node = parts; node != null; node = node.tail) {
      arguments.add(node.head);
    }
    String text(TypeInfo type) => type._text(variables);
    switch (TypeKind.values[kind]) {
      case .nominal:
        return arguments.isEmpty
            ? className
            : '$className<${arguments.map(text).join(', ')}>';
      case .nullable:
        final base = arguments.single;
        return base.kind == TypeKind.function.index
            ? '(${text(base)})?'
            : '${text(base)}?';
      case .futureOr:
        return 'FutureOr<${text(arguments.single)}>';
      case .parameter:
        return variables[shape];
      case .dynamicType:
        return 'dynamic';
      case .voidType:
        return 'void';
      case .never:
        return 'Never';
      case .nullType:
        return 'Null';
      case .record:
      case .function:
        final info = signature!;
        final parameters = [
          for (var i = 0; i < info.binders; i++) 'X${variables.length + i}',
        ];
        final scope = [...parameters, ...variables];
        final children = arguments.map((type) => type._text(scope)).toList();
        final record = kind == TypeKind.record.index;
        final offset = record ? 0 : info.binders + 1;
        final positional = children.sublist(offset, offset + info.positional);
        final entries = <String>[];
        if (info.required < positional.length) {
          entries.addAll(positional.take(info.required));
          entries.add('[${positional.skip(info.required).join(', ')}]');
        } else {
          entries.addAll(positional);
        }
        final named = <String>[];
        for (var node = info.named; node != null; node = node.next) {
          named.add(
            '${node.required ? 'required ' : ''}${children[node.slot]} ${node.text}',
          );
        }
        if (named.isNotEmpty) entries.add('{${named.join(', ')}}');
        final argumentsText = entries.join(', ');
        if (record) {
          return '($argumentsText${positional.length == 1 && named.isEmpty ? ',' : ''})';
        }
        final bounds = <String>[];
        for (var i = 0; i < parameters.length; i++) {
          bounds.add(
            children[i] == 'Object?'
                ? parameters[i]
                : '${parameters[i]} extends ${children[i]}',
          );
        }
        return '${children[info.binders]} Function${bounds.isEmpty ? '' : '<${bounds.join(', ')}>'}($argumentsText)';
    }
  }
}

/// Ordered child types without a dependency on managed List storage.
@TypeStorage(1)
final class TypeArguments(final TypeInfo head, final TypeArguments? tail) {
  @RuntimeEntry(.typeAt)
  static TypeInfo at(TypeArguments? values, int index) {
    var node = values!;
    for (var i = 0; i < index; i++) {
      node = node.tail!;
    }
    return node.head;
  }

  @RuntimeEntry(.typeArgumentsEqual)
  static bool equal(TypeArguments? left, TypeArguments? right) {
    while (left != null && right != null) {
      if (left.head != right.head) return false;
      left = left.tail;
      right = right.tail;
    }
    return left == null && right == null;
  }

  @RuntimeEntry(.typeArgumentsHash)
  static int hash(TypeArguments? values) {
    var result = 0;
    for (var node = values; node != null; node = node.tail) {
      result = _mix(result, node.head.hashCode);
    }
    return result;
  }

  static bool _subtypes(
    TypeArguments? left,
    TypeArguments? right,
    _TypeScope? sourceScope,
    _TypeScope? targetScope,
    _BoundCheck? active,
  ) {
    while (left != null && right != null) {
      if (!left.head._isSubtype(right.head, sourceScope, targetScope, active)) {
        return false;
      }
      left = left.tail;
      right = right.tail;
    }
    return left == null && right == null;
  }

  TypeArguments shift(int amount, int cutoff) =>
      TypeArguments(head.shift(amount, cutoff), tail?.shift(amount, cutoff));
}

/// Function or record parameter names and positional boundaries.
@TypeStorage(2)
final class FunctionInfo(
  final int binders,
  final int positional,
  final int required,
  final NamedParameter? named,
) {
  NamedParameter? find(int name) {
    for (var node = named; node != null; node = node.next) {
      if (node.name == name) return node;
    }
    return null;
  }
}

/// One named field or parameter in canonical name order.
@TypeStorage(3)
final class NamedParameter(
  final int name,
  final int slot,
  final bool required,
  final NamedParameter? next,
  final String text,
);

int _mix(int seed, int value) => (seed * 31 + value) & 0x3fffffff;

final class _TypeScope(
  final int count,
  final TypeArguments? bounds,
  final _TypeScope? outer,
  final _TypeScope? canonical,
) {
  final int total = count + (outer?.total ?? 0);
  _TypeScope get owner => canonical ?? this;

  _TypeScope scopeAt(int index) {
    var scope = this;
    while (index >= scope.count) {
      index -= scope.count;
      scope = scope.outer!;
    }
    return scope;
  }

  int slot(int index, _TypeScope scope) => index - (total - scope.total);
}

final class _BoundCheck(
  final _TypeScope owner,
  final int slot,
  final TypeInfo target,
  final _TypeScope? scope,
  final _BoundCheck? next,
);
