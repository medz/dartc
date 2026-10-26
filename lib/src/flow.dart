import 'types.dart';

const int flowUnassigned = 0;
const int flowAssigned = 1;
const int flowMaybeAssigned = 2;

class FlowState {
  List<int> types;
  List<int> assignments;
  List<bool> reachability;
  bool reachable;
  bool soundFlow = true;

  FlowState(this.types, this.assignments, this.reachability, this.reachable);
}

FlowState flowCreate(int count, [bool soundFlow = true]) {
  var result = FlowState(
    List<int>.filled(count, -1),
    List<int>.filled(count, flowUnassigned),
    <bool>[true],
    true,
  );
  result.soundFlow = soundFlow;
  return result;
}

FlowState flowCopy(FlowState state) {
  var result = FlowState(
    List<int>.filled(state.types.length, -1),
    List<int>.filled(state.types.length, flowUnassigned),
    List<bool>.filled(state.reachability.length, false, growable: true),
    state.reachable,
  );
  result.soundFlow = state.soundFlow;
  var i = 0;
  while (i < state.types.length) {
    result.types[i] = state.types[i];
    result.assignments[i] = state.assignments[i];
    i++;
  }
  i = 0;
  while (i < state.reachability.length) {
    result.reachability[i] = state.reachability[i];
    i++;
  }
  return result;
}

void flowUnreachable(FlowState state) {
  state.reachability[state.reachability.length - 1] = false;
  state.reachable = false;
}

FlowState flowSplit(FlowState state) {
  var result = flowCopy(state);
  result.reachability.add(true);
  return result;
}

FlowState flowUnsplitTo(FlowState state, int depth) {
  var result = flowCopy(state);
  while (result.reachability.length > depth) {
    var reached = result.reachability.removeLast();
    var parent = result.reachability.length - 1;
    result.reachability[parent] = result.reachability[parent] && reached;
  }
  return result;
}

FlowState flowUnsplit(FlowState state) {
  return flowUnsplitTo(state, state.reachability.length - 1);
}

FlowState flowJoin(FlowState left, FlowState right, List<int> declaredTypes) {
  if (left.reachability.length > right.reachability.length) {
    left = flowUnsplitTo(left, right.reachability.length);
  } else if (right.reachability.length > left.reachability.length) {
    right = flowUnsplitTo(right, left.reachability.length);
  }
  var depth = left.reachability.length;
  var leftReachable = left.reachability[depth - 1];
  var rightReachable = right.reachability[depth - 1];
  FlowState result;
  if (!leftReachable && rightReachable) {
    result = flowCopy(right);
  } else if (!rightReachable && leftReachable) {
    result = flowCopy(left);
  } else {
    result = FlowState(
      List<int>.filled(left.types.length, -1),
      List<int>.filled(left.types.length, flowMaybeAssigned),
      List<bool>.filled(depth, false, growable: true),
      true,
    );
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
      if (left.assignments[i] == right.assignments[i]) {
        result.assignments[i] = left.assignments[i];
      }
      i++;
    }
  }
  result.soundFlow = left.soundFlow;
  result.reachable = true;
  var i = 0;
  while (i < depth) {
    var reached = left.reachability[i] || right.reachability[i];
    result.reachability[i] = reached;
    result.reachable = result.reachable && reached;
    i++;
  }
  return result;
}

void flowDeclare(FlowState state, int binding, int type, bool assigned) {
  state.types[binding] = type;
  state.assignments[binding] = assigned ? flowAssigned : flowUnassigned;
}

void flowWrite(FlowState state, int binding, int declaredType, int valueType) {
  var current = state.types[binding];
  var type = declaredType;
  if (current >= 0 && typeIsSubtype(valueType, current)) {
    type = current;
  }
  if (!typeCanBeNull(valueType)) type = typeNonNullable(type);
  state.types[binding] = type;
  state.assignments[binding] = flowAssigned;
}

void flowPromote(FlowState state, int binding, int testedType) {
  var current = state.types[binding];
  if (current < 0 || current == tVoid || typeIsSubtype(current, testedType)) {
    return;
  }
  if (typeIsDisjoint(current, testedType)) {
    if (state.soundFlow &&
        (current == tNull && !typeCanBeNull(testedType) ||
            !typeCanBeNull(current) && testedType == tNull)) {
      flowUnreachable(state);
    }
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
    if (state.soundFlow) flowUnreachable(state);
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
  if (state.soundFlow && equalsNull && !typeCanBeNull(current) ||
      !equalsNull && current == tNull) {
    flowUnreachable(state);
  }
  if (!equalsNull) state.types[binding] = typeNonNullable(current);
}

void flowDemote(FlowState state, List<int> written, List<int> declaredTypes) {
  var i = 0;
  while (i < written.length) {
    var binding = written[i];
    state.types[binding] = declaredTypes[binding];
    if (state.assignments[binding] == flowUnassigned) {
      state.assignments[binding] = flowMaybeAssigned;
    }
    i++;
  }
}
