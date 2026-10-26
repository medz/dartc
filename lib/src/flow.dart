import 'types.dart';

class FlowState {
  List<int> types;
  List<bool> assigned;
  bool reachable;

  FlowState(this.types, this.assigned, this.reachable);
}

FlowState flowCreate(int count) {
  return FlowState(
    List<int>.filled(count, -1),
    List<bool>.filled(count, false),
    true,
  );
}

FlowState flowCopy(FlowState state) {
  var result = flowCreate(state.types.length);
  result.reachable = state.reachable;
  var i = 0;
  while (i < state.types.length) {
    result.types[i] = state.types[i];
    result.assigned[i] = state.assigned[i];
    i++;
  }
  return result;
}

FlowState flowJoin(FlowState left, FlowState right, List<int> declaredTypes) {
  if (!left.reachable && right.reachable) return flowCopy(right);
  if (!right.reachable && left.reachable) return flowCopy(left);
  var result = flowCreate(left.types.length);
  result.reachable = left.reachable || right.reachable;
  var i = 0;
  while (i < left.types.length) {
    var type = declaredTypes[i];
    if (left.types[i] >= 0 && right.types[i] >= 0) {
      type = joinTypes(left.types[i], right.types[i]);
      if (declaredTypes[i] >= 0 && !typeIsSubtype(type, declaredTypes[i])) {
        type = declaredTypes[i];
      }
    }
    result.types[i] = type;
    result.assigned[i] = left.assigned[i] && right.assigned[i];
    i++;
  }
  return result;
}

void flowDeclare(FlowState state, int binding, int type, bool assigned) {
  state.types[binding] = type;
  state.assigned[binding] = assigned;
}

void flowWrite(FlowState state, int binding, int declaredType, int valueType) {
  var current = state.types[binding];
  var type = declaredType;
  if (current >= 0 && typeIsSubtype(valueType, current)) {
    type = current;
  }
  if (!typeCanBeNull(valueType)) type = typeNonNullable(type);
  state.types[binding] = type;
  state.assigned[binding] = true;
}

void flowPromote(FlowState state, int binding, int testedType) {
  var current = state.types[binding];
  if (current < 0 || current == tVoid || typeIsSubtype(current, testedType)) {
    return;
  }
  if (typeIsDisjoint(current, testedType)) {
    state.reachable = false;
    return;
  }
  var promoted = testedType;
  if (!typeCanBeNull(current)) promoted = typeNonNullable(promoted);
  if (typeIsSubtype(promoted, current)) {
    state.types[binding] = promoted;
  } else if (typeIsNullable(current) &&
      !typeCanBeNull(testedType) &&
      typeIsSubtype(typeNonNullable(current), testedType)) {
    state.types[binding] = typeNonNullable(current);
  }
}

void flowExclude(FlowState state, int binding, int testedType) {
  var current = state.types[binding];
  if (current < 0 || current == tVoid) return;
  if (typeIsSubtype(current, testedType)) {
    state.reachable = false;
    return;
  }
  if (typeCanBeNull(testedType)) {
    flowNull(state, binding, false);
  } else if (current != tDynamic &&
      typeCanBeNull(current) &&
      !typeCanBeNull(testedType) &&
      (testedType == tObject ||
          typeIsSubtype(typeNonNullable(current), testedType))) {
    state.types[binding] = tNull;
  }
}

void flowNull(FlowState state, int binding, bool equalsNull) {
  var current = state.types[binding];
  if (current < 0) return;
  if (equalsNull && !typeCanBeNull(current) ||
      !equalsNull && current == tNull) {
    state.reachable = false;
  }
  if (!equalsNull) state.types[binding] = typeNonNullable(current);
}

void flowDemote(FlowState state, List<int> written, List<int> declaredTypes) {
  var i = 0;
  while (i < written.length) {
    var binding = written[i];
    state.types[binding] = declaredTypes[binding];
    i++;
  }
}
