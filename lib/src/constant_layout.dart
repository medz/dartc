import 'code.dart';
import 'constant_data.dart';
import 'frame.dart';
import 'host.dart';
import 'ir.dart';
import 'layout.dart';
import 'root_map.dart';
import 'types.dart';

class CaptureDescriptor {
  final List<int> references;
  final List<int> tagged;
  int offset = -1;
  int referencesOffset = -1;
  int taggedOffset = -1;

  CaptureDescriptor(this.references, this.tagged);
}

CaptureDescriptor _captureDescriptor(List<int> types, int prefix) {
  var words = (prefix + types.length + 63) ~/ 64;
  var references = List<int>.filled(words, 0);
  var tagged = List<int>.filled(words, 0);
  var i = 0;
  while (i < types.length) {
    var field = prefix + i;
    var word = field ~/ 64;
    var bit = 1 << (field & 63);
    if (typeIsReference(types[i]))
      references[word] |= bit;
    else if (typeIsTagged(types[i]))
      tagged[word] |= bit;
    i++;
  }
  return CaptureDescriptor(references, tagged);
}

class ConstantLayout {
  List<int> stringOffsets;
  List<int> descriptorOffsets;
  List<int> classNameStrings;
  List<int> typeOffsets;
  int stringDescriptorOffset;
  int listDescriptorOffset;
  int wordArrayDescriptorOffset;
  int refArrayDescriptorOffset;
  int taggedArrayDescriptorOffset;
  int intBoxDescriptorOffset;
  int doubleBoxDescriptorOffset = -1;
  int handleTypeOffset;
  int metadataOffset;
  int end;
  List<int> globalOffsets = <int>[];
  int globalBytes = 0;
  List<int> dataOffsets = <int>[];
  List<int> callableOffsets = <int>[];
  List<int> signatureOffsets = <int>[];
  List<int> callShapeOffsets = <int>[];
  List<int> classSubtypeOffsets = <int>[];
  List<List<int>> classSubtypes = <List<int>>[];
  List<CaptureDescriptor?> closureDescriptors = <CaptureDescriptor?>[];
  List<CaptureDescriptor?> captureCellDescriptors = <CaptureDescriptor?>[];
  List<CaptureDescriptor?> lateCellDescriptors = <CaptureDescriptor?>[];
  int functionDescriptorOffset = -1;
  int typeDescriptorOffset = -1;
  List<int> refBitmapOffsets = <int>[];
  List<int> taggedBitmapOffsets = <int>[];
  int metadataFeatures = 0;
  int metadataBytes = 0;
  int rootTableOffset = -1;
  int rootCallsOffset = -1;
  List<int> rootSlotOffsets = <int>[];
  int globalRootsOffset = -1;
  List<int> globalRoots = <int>[];
  int frameTableOffset = -1;
  int frameDescriptorsOffset = -1;
  List<int> frameNameStrings = <int>[];
  int handlerTableOffset = -1;
  int handlerEntriesOffset = -1;

  ConstantLayout(
    this.stringOffsets,
    this.descriptorOffsets,
    this.classNameStrings,
    this.typeOffsets,
    this.stringDescriptorOffset,
    this.listDescriptorOffset,
    this.wordArrayDescriptorOffset,
    this.refArrayDescriptorOffset,
    this.taggedArrayDescriptorOffset,
    this.intBoxDescriptorOffset,
    this.handleTypeOffset,
    this.metadataOffset,
    this.end,
  );
}

void _markTypeReference(
  List<int> offsets,
  List<int> work,
  int type, [
  bool template = false,
]) {
  if (typeHasSchemaHole(type) || typeContainsParameters(type) && !template) {
    print('dartc: uninstantiated runtime type');
    hostExit(1);
  }
  if (ffiKind(type) >= 0) {
    print('dartc: FFI native types do not have runtime type metadata yet');
    hostExit(1);
  }
  if (offsets[type] < 0) {
    offsets[type] = 0;
    work.add(type);
  }
}

bool _bitmapNonzero(List<int> words) {
  var i = 0;
  while (i < words.length) {
    if (words[i] != 0) return true;
    i++;
  }
  return false;
}

int _rootSlotsHash(CallRootMap roots) {
  var hash = roots.offsets.length & 0x3fffffff;
  var i = 0;
  while (i < roots.offsets.length) {
    hash = (hash * 31 + roots.offsets[i]) & 0x3fffffff;
    hash = (hash * 31 + roots.kinds[i]) & 0x3fffffff;
    i++;
  }
  return hash;
}

bool _sameRootSlots(CallRootMap left, CallRootMap right) {
  if (left.offsets.length != right.offsets.length) return false;
  var i = 0;
  while (i < left.offsets.length) {
    if (left.offsets[i] != right.offsets[i] || left.kinds[i] != right.kinds[i])
      return false;
    i++;
  }
  return true;
}

ConstantLayout layoutConstants(int start) {
  List<int> stringOffsets = <int>[];
  List<int> descriptorOffsets = <int>[];
  List<int> classNameStrings = <int>[];
  List<int> typeOffsets = <int>[];
  List<int> dataOffsets = <int>[];
  List<int> callableOffsets = <int>[];
  List<CaptureDescriptor?> closureDescriptors = <CaptureDescriptor?>[];
  List<CaptureDescriptor?> captureCellDescriptors = <CaptureDescriptor?>[];
  List<CaptureDescriptor?> lateCellDescriptors = <CaptureDescriptor?>[];
  List<int> signatureOffsets = <int>[];
  final callShapeOffsets = List<int>.filled(callShapes.length, -1);
  List<int> refBitmapOffsets = <int>[];
  List<int> taggedBitmapOffsets = <int>[];
  List<int> globalOffsets = <int>[];
  List<int> types = <int>[];
  int i = 0;
  while (i < strings.length) {
    stringOffsets.add(-1);
    i++;
  }
  i = 0;
  while (i < classSizes.length) {
    descriptorOffsets.add(-1);
    classNameStrings.add(-1);
    refBitmapOffsets.add(-1);
    taggedBitmapOffsets.add(-1);
    i++;
  }
  i = 0;
  while (i < dartTypes.length) {
    typeOffsets.add(-1);
    i++;
  }
  i = 0;
  while (i < constantData.length) {
    dataOffsets.add(-1);
    i++;
  }
  i = 0;
  while (i < functions.length) {
    callableOffsets.add(-1);
    closureDescriptors.add(null);
    i++;
  }
  i = 0;
  while (i < dartTypes.length) {
    captureCellDescriptors.add(null);
    lateCellDescriptors.add(null);
    i++;
  }
  i = 0;
  while (i < globalNames.length) {
    globalOffsets.add(-1);
    i++;
  }
  int features = 0;
  i = 0;
  while (i < codeAddresses.length) {
    if (codeAddresses[i].kind == 0) {
      stringOffsets[codeAddresses[i].target] = 0;
    } else if (codeAddresses[i].kind == 1) {
      globalOffsets[codeAddresses[i].target] = 0;
    } else if (codeAddresses[i].kind == 2) {
      descriptorOffsets[codeAddresses[i].target] = 0;
    } else if (codeAddresses[i].kind == 3) {
      features = features | codeAddresses[i].target;
    } else if (codeAddresses[i].kind == 4) {
      _markTypeReference(typeOffsets, types, codeAddresses[i].target);
    } else if (codeAddresses[i].kind == 9) {
      _markTypeReference(typeOffsets, types, codeAddresses[i].target, true);
    } else if (codeAddresses[i].kind == 5) {
      dataOffsets[codeAddresses[i].target] = 0;
    } else if (codeAddresses[i].kind == 6) {
      callableOffsets[codeAddresses[i].target] = 0;
    } else if (codeAddresses[i].kind == 7) {
      var function = codeAddresses[i].target;
      if (closureDescriptors[function] == null)
        closureDescriptors[function] = _captureDescriptor(
          functions[function].closureLayout!.fieldTypes,
          (functionInstanceBytes - objectHeaderBytes) ~/ 8,
        );
    } else if (codeAddresses[i].kind == 8) {
      var type = codeAddresses[i].target;
      if (captureCellDescriptors[type] == null)
        captureCellDescriptors[type] = _captureDescriptor(<int>[type], 0);
    } else if (codeAddresses[i].kind == 11) {
      final shape = codeAddresses[i].target;
      callShapeOffsets[shape] = 0;
      for (final name in callShapes[shape].names) {
        final string = internString(name);
        while (stringOffsets.length < strings.length) stringOffsets.add(-1);
        stringOffsets[string] = 0;
      }
    } else if (codeAddresses[i].kind == 10) {
      final type = codeAddresses[i].target;
      lateCellDescriptors[type] ??= _captureDescriptor(<int>[
        type,
        tBool,
        tFunction,
      ], 0);
    }
    i++;
  }
  var globalBytes = 0;
  i = 0;
  while (i < globalOffsets.length) {
    if (globalOffsets[i] == 0) {
      globalOffsets[i] = globalBytes;
      globalBytes += 8;
    }
    i++;
  }
  i = 0;
  while (i < constantData.length) {
    if (dataOffsets[i] == 0) {
      var data = constantData[i];
      _markTypeReference(typeOffsets, types, data.type);
      var value = 0;
      while (value < data.kinds.length) {
        if (data.kinds[value] == typeKindString) {
          stringOffsets[data.values[value]] = 0;
        } else if (data.kinds[value] == typeKindFunction) {
          callableOffsets[data.values[value]] = 0;
        }
        value++;
      }
    }
    i++;
  }
  bool needsFunctions = false;
  i = 0;
  while (i < callableOffsets.length) {
    if (callableOffsets[i] == 0 || closureDescriptors[i] != null) {
      if (callableOffsets[i] == 0) needsFunctions = true;
      var type = functionValueType(i);
      while (typeOffsets.length < dartTypes.length) typeOffsets.add(-1);
      _markTypeReference(
        typeOffsets,
        types,
        type,
        functions[i].closureLayout?.typeParameters.isNotEmpty ?? false,
      );
    }
    i++;
  }
  i = 0;
  while (i < functionSignatures.length) {
    signatureOffsets.add(-1);
    i++;
  }
  if (emittedHandlers.isNotEmpty) features |= metadataHandlers;
  final needsHandlers = (features & metadataHandlers) != 0;
  if (needsHandlers) features |= metadataFrames;
  final needsFrames = (features & metadataFrames) != 0;
  final frameNameStrings = <int>[];
  if (needsFrames) {
    features |= metadataStrings;
    for (final frame in emittedFrames) {
      var name = -1;
      if (frame.function >= 0) {
        final declared = functions[frame.function].name;
        name = internString(declared == '' ? '<anonymous closure>' : declared);
        while (stringOffsets.length < strings.length) stringOffsets.add(-1);
        stringOffsets[name] = 0;
      }
      frameNameStrings.add(name);
    }
  }
  bool needsValues = (features & metadataValues) != 0;
  int handleType = -1;
  if (needsValues) {
    features = features | metadataStrings | metadataLists;
    handleType = listType(tObject);
    while (typeOffsets.length < dartTypes.length) typeOffsets.add(-1);
    _markTypeReference(typeOffsets, types, handleType);
  }
  i = 0;
  while (i < types.length) {
    var type = dartTypes[types[i]];
    if (type.kind == kList || type.kind == kNullable) {
      _markTypeReference(
        typeOffsets,
        types,
        type.argument,
        type.containsParameters,
      );
    } else if (type.kind == kClass) {
      descriptorOffsets[type.argument] = 0;
    } else if (type.kind == kFunction) {
      signatureOffsets[type.argument] = 0;
      var signature = functionSignatures[type.argument];
      for (final name in signature.names) {
        final string = internString(name);
        while (stringOffsets.length < strings.length) stringOffsets.add(-1);
        stringOffsets[string] = 0;
      }
      _markTypeReference(
        typeOffsets,
        types,
        signature.result,
        type.containsParameters,
      );
      var p = 0;
      while (p < signature.parameters.length) {
        _markTypeReference(
          typeOffsets,
          types,
          signature.parameters[p],
          type.containsParameters,
        );
        p++;
      }
    }
    i++;
  }
  if (needsValues) {
    i = 0;
    while (i < descriptorOffsets.length) {
      if (descriptorOffsets[i] == 0) {
        int name = internString(classNames[i]);
        classNameStrings[i] = name;
        while (stringOffsets.length < strings.length) stringOffsets.add(-1);
        stringOffsets[name] = 0;
      }
      i++;
    }
  }
  bool needsMetadata = features != 0;
  bool needsLists = (features & metadataLists) != 0;
  bool needsRoots = (features & metadataRoots) != 0;
  int end = start;
  bool needsStringDescriptor = (features & metadataStrings) != 0;
  i = 0;
  while (i < strings.length) {
    if (stringOffsets[i] == 0) {
      stringOffsets[i] = end;
      int bytes = stringDataOffset + strings[i].length * 2;
      end = end + ((bytes + 7) & -8);
      needsStringDescriptor = true;
    }
    i++;
  }
  i = 0;
  while (i < classSizes.length) {
    if (descriptorOffsets[i] == 0) {
      descriptorOffsets[i] = end;
      end = end + classDescriptorBytes;
    }
    i++;
  }
  int stringDescriptorOffset = -1;
  if (needsStringDescriptor) {
    stringDescriptorOffset = end;
    end = end + classDescriptorBytes;
  }
  int listDescriptorOffset = -1;
  int wordArrayDescriptorOffset = -1;
  int refArrayDescriptorOffset = -1;
  if (needsLists) {
    listDescriptorOffset = end;
    end = end + classDescriptorBytes;
    wordArrayDescriptorOffset = end;
    end = end + classDescriptorBytes;
    refArrayDescriptorOffset = end;
    end = end + classDescriptorBytes;
  }
  int taggedArrayDescriptorOffset = -1;
  int intBoxDescriptorOffset = -1;
  int doubleBoxDescriptorOffset = -1;
  if (needsLists) {
    taggedArrayDescriptorOffset = end;
    end = end + classDescriptorBytes;
  }
  if (needsValues) {
    intBoxDescriptorOffset = end;
    end += classDescriptorBytes;
    doubleBoxDescriptorOffset = end;
    end += classDescriptorBytes;
  }
  int functionDescriptorOffset = -1;
  if (needsFunctions) {
    functionDescriptorOffset = end;
    end += classDescriptorBytes;
  }
  int typeDescriptorOffset = -1;
  if (types.isNotEmpty) {
    typeDescriptorOffset = end;
    end += classDescriptorBytes;
  }
  for (var descriptors in <List<CaptureDescriptor?>>[
    closureDescriptors,
    captureCellDescriptors,
    lateCellDescriptors,
  ]) {
    for (var descriptor in descriptors) {
      if (descriptor != null) {
        descriptor.offset = end;
        end += classDescriptorBytes;
      }
    }
  }
  i = 0;
  while (i < classSizes.length) {
    if (descriptorOffsets[i] >= 0) {
      var fields = (classSizes[i] - objectHeaderBytes) ~/ 8;
      var bytes = ((fields + 63) ~/ 64) * 8;
      if (_bitmapNonzero(classPointerMasks[i])) {
        refBitmapOffsets[i] = end;
        end += bytes;
      }
      if (_bitmapNonzero(classTaggedMasks[i])) {
        taggedBitmapOffsets[i] = end;
        end += bytes;
      }
    }
    i++;
  }
  for (var descriptors in <List<CaptureDescriptor?>>[
    closureDescriptors,
    captureCellDescriptors,
    lateCellDescriptors,
  ]) {
    for (var descriptor in descriptors) {
      if (descriptor != null) {
        if (_bitmapNonzero(descriptor.references)) {
          descriptor.referencesOffset = end;
          end += descriptor.references.length * 8;
        }
        if (_bitmapNonzero(descriptor.tagged)) {
          descriptor.taggedOffset = end;
          end += descriptor.tagged.length * 8;
        }
      }
    }
  }
  i = 0;
  while (i < typeOffsets.length) {
    if (typeOffsets[i] == 0) {
      typeOffsets[i] = end;
      end = end + typeRefBytes;
    }
    i++;
  }
  i = 0;
  while (i < signatureOffsets.length) {
    if (signatureOffsets[i] == 0) {
      signatureOffsets[i] = end;
      end +=
          functionSignatureParametersOffset +
          functionSignatures[i].parameters.length * 8 +
          functionSignatures[i].names.length * functionSignatureNamedEntryBytes;
    }
    i++;
  }
  final classSubtypeOffsets = List<int>.filled(typeOffsets.length, -1);
  for (var i = 0; i < callShapeOffsets.length; i++) {
    if (callShapeOffsets[i] < 0) continue;
    callShapeOffsets[i] = end;
    end += callShapeNamesOffset + callShapes[i].names.length * 8;
  }
  final classSubtypes = <List<int>>[];
  for (var type = 0; type < typeOffsets.length; type++) {
    final subtypes = <int>[];
    if (typeOffsets[type] >= 0 && typeIsClass(type)) {
      for (var owner = 0; owner < descriptorOffsets.length; owner++) {
        if (descriptorOffsets[owner] >= 0 &&
            typeArgument(type) != owner &&
            typeIsSubtype(classType(owner), type))
          subtypes.add(owner);
      }
    }
    if (subtypes.isNotEmpty) {
      classSubtypeOffsets[type] = end;
      end += classSubtypeEntriesOffset + subtypes.length * 8;
    }
    classSubtypes.add(subtypes);
  }
  int handleTypeOffset = -1;
  if (needsValues) handleTypeOffset = typeOffsets[handleType];
  int metadataOffset = -1;
  int metadataBytes = 0;
  if (needsMetadata) {
    metadataOffset = end;
    metadataBytes = metadataStringDescriptorOffset + 8;
    if (needsLists) metadataBytes = metadataTaggedArrayDescriptorOffset + 8;
    if (needsRoots) metadataBytes = metadataRootTableOffset + 8;
    if (needsValues) metadataBytes = metadataDoubleBoxDescriptorOffset + 8;
    if (needsFrames) metadataBytes = metadataFrameTableOffset + 8;
    if (needsHandlers) metadataBytes = metadataHandlerTableOffset + 8;
    end += metadataBytes;
  }
  int rootTableOffset = -1;
  int rootCallsOffset = -1;
  List<int> rootSlotOffsets = <int>[];
  int globalRootsOffset = -1;
  List<int> globalRoots = <int>[];
  if (needsRoots) {
    rootTableOffset = end;
    end += rootTableBytes;
    if (emittedRootMaps.isNotEmpty) {
      rootCallsOffset = end;
      end += emittedRootMaps.length * rootCallBytes;
    }
    var capacity = 1;
    while (capacity < emittedRootMaps.length * 2) capacity *= 2;
    var owners = List<int>.filled(capacity, -1);
    i = 0;
    while (i < emittedRootMaps.length) {
      var roots = emittedRootMaps[i];
      var offset = -1;
      if (!roots.boundary && roots.offsets.isNotEmpty) {
        var slot = _rootSlotsHash(roots) & (capacity - 1);
        while (owners[slot] >= 0 &&
            !_sameRootSlots(roots, emittedRootMaps[owners[slot]])) {
          slot = (slot + 1) & (capacity - 1);
        }
        var owner = owners[slot];
        if (owner < 0) {
          owners[slot] = i;
          offset = end;
          end += roots.offsets.length * rootSlotBytes;
        } else {
          offset = rootSlotOffsets[owner];
        }
      }
      rootSlotOffsets.add(offset);
      i++;
    }
    i = 0;
    while (i < globalTypes.length) {
      if (globalOffsets[i] >= 0 &&
          (typeIsReference(globalTypes[i]) || typeIsTagged(globalTypes[i]))) {
        globalRoots.add(i);
      }
      i++;
    }
    if (globalRoots.isNotEmpty) {
      globalRootsOffset = end;
      end += globalRoots.length * globalRootBytes;
    }
  }
  var frameTableOffset = -1;
  var frameDescriptorsOffset = -1;
  if (needsFrames) {
    frameTableOffset = end;
    end += frameTableBytes;
    frameDescriptorsOffset = end;
    end += emittedFrames.length * frameDescriptorBytes;
  }
  var handlerTableOffset = -1;
  var handlerEntriesOffset = -1;
  if (needsHandlers) {
    handlerTableOffset = end;
    end += handlerTableBytes;
    handlerEntriesOffset = end;
    end += emittedHandlers.length * handlerEntryBytes;
  }
  end = (end + 7) & -8;
  i = 0;
  while (i < constantData.length) {
    if (dataOffsets[i] == 0) {
      dataOffsets[i] = end;
      var data = constantData[i];
      var entryBytes = 8;
      var headerBytes = constantListDataOffset;
      if (typeIsClass(data.type)) {
        headerBytes = constantObjectDataOffset;
        entryBytes = constantObjectEntryBytes;
      } else if (typeIsTagged(typeArgument(data.type))) {
        entryBytes = constantListTaggedEntryBytes;
      }
      end = end + headerBytes + data.values.length * entryBytes;
    }
    i++;
  }
  i = 0;
  while (i < callableOffsets.length) {
    if (callableOffsets[i] == 0) {
      callableOffsets[i] = end;
      end += functionInstanceBytes;
    }
    i++;
  }
  return ConstantLayout(
      stringOffsets,
      descriptorOffsets,
      classNameStrings,
      typeOffsets,
      stringDescriptorOffset,
      listDescriptorOffset,
      wordArrayDescriptorOffset,
      refArrayDescriptorOffset,
      taggedArrayDescriptorOffset,
      intBoxDescriptorOffset,
      handleTypeOffset,
      metadataOffset,
      end,
    )
    ..globalOffsets = globalOffsets
    ..globalBytes = globalBytes
    ..dataOffsets = dataOffsets
    ..callableOffsets = callableOffsets
    ..closureDescriptors = closureDescriptors
    ..captureCellDescriptors = captureCellDescriptors
    ..lateCellDescriptors = lateCellDescriptors
    ..signatureOffsets = signatureOffsets
    ..callShapeOffsets = callShapeOffsets
    ..classSubtypeOffsets = classSubtypeOffsets
    ..classSubtypes = classSubtypes
    ..functionDescriptorOffset = functionDescriptorOffset
    ..typeDescriptorOffset = typeDescriptorOffset
    ..refBitmapOffsets = refBitmapOffsets
    ..taggedBitmapOffsets = taggedBitmapOffsets
    ..metadataFeatures = features
    ..doubleBoxDescriptorOffset = doubleBoxDescriptorOffset
    ..metadataBytes = metadataBytes
    ..rootTableOffset = rootTableOffset
    ..rootCallsOffset = rootCallsOffset
    ..rootSlotOffsets = rootSlotOffsets
    ..globalRootsOffset = globalRootsOffset
    ..globalRoots = globalRoots
    ..frameTableOffset = frameTableOffset
    ..frameDescriptorsOffset = frameDescriptorsOffset
    ..frameNameStrings = frameNameStrings
    ..handlerTableOffset = handlerTableOffset
    ..handlerEntriesOffset = handlerEntriesOffset;
}
