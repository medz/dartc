import 'arm64.dart';
import 'constant_data.dart';
import 'ir.dart';
import 'layout.dart';
import 'root_map.dart';
import 'sign.dart';
import 'types.dart';

List<int> image = <int>[];

void image32(int value) {
  image.add(value & 255);
  image.add((value >> 8) & 255);
  image.add((value >> 16) & 255);
  image.add((value >> 24) & 255);
}

void image64(int value) {
  image32(value & 0xffffffff);
  image32(value >> 32);
}

void imageName(String name, int width) {
  int i = 0;
  while (i < width) {
    if (i < name.length) {
      image.add(name.codeUnitAt(i));
    } else {
      image.add(0);
    }
    i = i + 1;
  }
}

void imageZeros(int count) {
  int i = 0;
  while (i < count) {
    image.add(0);
    i = i + 1;
  }
}

void imagePatch32(int offset, int value) {
  image[offset] = value & 255;
  image[offset + 1] = (value >> 8) & 255;
  image[offset + 2] = (value >> 16) & 255;
  image[offset + 3] = (value >> 24) & 255;
}

int alignImage(int value, int alignment) {
  return (value + alignment - 1) & ~(alignment - 1);
}

void imageSegment(
  String name,
  int address,
  int memorySize,
  int offset,
  int fileSize,
  int protection,
  int sections,
) {
  image32(0x19);
  image32(72 + sections * 80);
  imageName(name, 16);
  image64(address);
  image64(memorySize);
  image64(offset);
  image64(fileSize);
  image32(protection);
  image32(protection);
  image32(sections);
  image32(0);
}

void imageSection(
  String name,
  String segment,
  int address,
  int offset,
  int size,
  int flags,
) {
  imageName(name, 16);
  imageName(segment, 16);
  image64(address);
  image64(size);
  image32(offset);
  image32(3);
  image32(0);
  image32(0);
  image32(flags);
  image32(0);
  image32(0);
  image32(0);
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
  int handleTypeOffset;
  int metadataOffset;
  int end;
  List<int> globalOffsets = <int>[];
  int globalBytes = 0;
  List<int> dataOffsets = <int>[];
  List<int> callableOffsets = <int>[];
  List<int> signatureOffsets = <int>[];
  int functionDescriptorOffset = -1;
  List<int> refBitmapOffsets = <int>[];
  List<int> taggedBitmapOffsets = <int>[];
  int metadataFeatures = 0;
  int metadataBytes = 0;
  int rootTableOffset = -1;
  int rootCallsOffset = -1;
  List<int> rootSlotOffsets = <int>[];
  int globalRootsOffset = -1;
  List<int> globalRoots = <int>[];

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

void markTypeReference(List<int> offsets, List<int> work, int type) {
  if (offsets[type] < 0) {
    offsets[type] = 0;
    work.add(type);
  }
}

bool bitmapNonzero(List<int> words) {
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
  List<int> signatureOffsets = <int>[];
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
    i++;
  }
  i = 0;
  while (i < globalNames.length) {
    globalOffsets.add(-1);
    i++;
  }
  int features = 0;
  i = 0;
  while (i < addressKinds.length) {
    if (addressKinds[i] == 0) {
      stringOffsets[addressTargets[i]] = 0;
    } else if (addressKinds[i] == 1) {
      globalOffsets[addressTargets[i]] = 0;
    } else if (addressKinds[i] == 2) {
      descriptorOffsets[addressTargets[i]] = 0;
    } else if (addressKinds[i] == 3) {
      features = features | addressTargets[i];
    } else if (addressKinds[i] == 4) {
      markTypeReference(typeOffsets, types, addressTargets[i]);
    } else if (addressKinds[i] == 5) {
      dataOffsets[addressTargets[i]] = 0;
    } else if (addressKinds[i] == 6) {
      callableOffsets[addressTargets[i]] = 0;
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
      markTypeReference(typeOffsets, types, data.type);
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
    if (callableOffsets[i] == 0) {
      needsFunctions = true;
      var type = functionValueType(i);
      while (typeOffsets.length < dartTypes.length) typeOffsets.add(-1);
      markTypeReference(typeOffsets, types, type);
    }
    i++;
  }
  i = 0;
  while (i < functionSignatures.length) {
    signatureOffsets.add(-1);
    i++;
  }
  bool needsValues = (features & metadataValues) != 0;
  int handleType = -1;
  if (needsValues) {
    features = features | metadataStrings | metadataLists;
    handleType = listType(tObject);
    while (typeOffsets.length < dartTypes.length) typeOffsets.add(-1);
    markTypeReference(typeOffsets, types, handleType);
  }
  i = 0;
  while (i < types.length) {
    var type = dartTypes[types[i]];
    if (type.kind == kList || type.kind == kNullable) {
      markTypeReference(typeOffsets, types, type.argument);
    } else if (type.kind == kClass) {
      descriptorOffsets[type.argument] = 0;
    } else if (type.kind == kFunction) {
      signatureOffsets[type.argument] = 0;
      var signature = functionSignatures[type.argument];
      markTypeReference(typeOffsets, types, signature.result);
      var p = 0;
      while (p < signature.parameters.length) {
        markTypeReference(typeOffsets, types, signature.parameters[p]);
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
      end = end + alignImage(bytes, 8);
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
  if (needsLists) {
    taggedArrayDescriptorOffset = end;
    end = end + classDescriptorBytes;
  }
  if (needsValues) {
    intBoxDescriptorOffset = end;
    end = end + classDescriptorBytes;
  }
  int functionDescriptorOffset = -1;
  if (needsFunctions) {
    functionDescriptorOffset = end;
    end += classDescriptorBytes;
  }
  i = 0;
  while (i < classSizes.length) {
    if (descriptorOffsets[i] >= 0) {
      var fields = (classSizes[i] - objectHeaderBytes) ~/ 8;
      var bytes = ((fields + 63) ~/ 64) * 8;
      if (bitmapNonzero(classPointerMasks[i])) {
        refBitmapOffsets[i] = end;
        end += bytes;
      }
      if (bitmapNonzero(classTaggedMasks[i])) {
        taggedBitmapOffsets[i] = end;
        end += bytes;
      }
    }
    i++;
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
          functionSignatures[i].parameters.length * 8;
    }
    i++;
  }
  int handleTypeOffset = -1;
  if (needsValues) handleTypeOffset = typeOffsets[handleType];
  int metadataOffset = -1;
  int metadataBytes = 0;
  if (needsMetadata) {
    metadataOffset = end;
    metadataBytes = metadataStringDescriptorOffset + 8;
    if (needsLists) metadataBytes = metadataTaggedArrayDescriptorOffset + 8;
    if (needsValues) metadataBytes = metadataHandleTypeOffset + 8;
    if (needsRoots) metadataBytes = metadataRootTableOffset + 8;
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
  end = alignImage(end, 8);
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
  var layout = ConstantLayout(
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
  );
  layout.globalOffsets = globalOffsets;
  layout.globalBytes = globalBytes;
  layout.dataOffsets = dataOffsets;
  layout.callableOffsets = callableOffsets;
  layout.signatureOffsets = signatureOffsets;
  layout.functionDescriptorOffset = functionDescriptorOffset;
  layout.refBitmapOffsets = refBitmapOffsets;
  layout.taggedBitmapOffsets = taggedBitmapOffsets;
  layout.metadataFeatures = features;
  layout.metadataBytes = metadataBytes;
  layout.rootTableOffset = rootTableOffset;
  layout.rootCallsOffset = rootCallsOffset;
  layout.rootSlotOffsets = rootSlotOffsets;
  layout.globalRootsOffset = globalRootsOffset;
  layout.globalRoots = globalRoots;
  return layout;
}

List<int> createMachOExecutable() {
  int base = 0x100000000;
  int dataBase = 0x110000000;
  int page = 0x4000;
  int codeOffset = 0x1000;
  int constantOffset = alignImage(codeOffset + machineCode.length * 4, 8);
  ConstantLayout constants = layoutConstants(constantOffset);
  int payloadEnd = constants.end;
  int textSize = alignImage(payloadEnd, page);
  int dataSize = alignImage(constants.globalBytes, page);
  int site = 0;
  while (site < addressSites.length) {
    int target = 0;
    if (addressKinds[site] == 0) {
      target = base + constants.stringOffsets[addressTargets[site]];
    } else if (addressKinds[site] == 1) {
      target = dataBase + constants.globalOffsets[addressTargets[site]];
    } else if (addressKinds[site] == 2) {
      target = base + constants.descriptorOffsets[addressTargets[site]];
    } else if (addressKinds[site] == 3) {
      target = base + constants.metadataOffset;
    } else if (addressKinds[site] == 5) {
      target = base + constants.dataOffsets[addressTargets[site]];
    } else if (addressKinds[site] == 6) {
      target = base + constants.callableOffsets[addressTargets[site]];
    } else {
      target = base + constants.typeOffsets[addressTargets[site]];
    }
    int word = addressSites[site];
    int pc = base + codeOffset + word * 4;
    int pages = ((target >> 12) - (pc >> 12)) & 0x1fffff;
    machineCode[word] = 0x90000000 | ((pages & 3) << 29) | ((pages >> 2) << 5);
    machineCode[word + 1] = 0x91000000 | ((target & 0xfff) << 10);
    site = site + 1;
  }

  image = <int>[];
  image32(0xfeedfacf);
  image32(0x100000c);
  image32(0);
  image32(2);
  image32(13);
  image32(0);
  image32(0x200085);
  image32(0);
  imageSegment('__PAGEZERO', 0, base, 0, 0, 0, 0);
  imageSegment('__TEXT', base, textSize, 0, textSize, 5, 2);
  imageSection(
    '__text',
    '__TEXT',
    base + codeOffset,
    codeOffset,
    machineCode.length * 4,
    0x80000400,
  );
  imageSection(
    '__const',
    '__TEXT',
    base + constantOffset,
    constantOffset,
    payloadEnd - constantOffset,
    0,
  );
  imageSegment('__DATA', dataBase, dataSize, textSize, 0, 3, 1);
  imageSection('__bss', '__DATA', dataBase, 0, constants.globalBytes, 1);
  int linkeditCommand = image.length;
  imageSegment('__LINKEDIT', dataBase + dataSize, page, textSize, 16, 1, 0);

  image32(0xe);
  image32(32);
  image32(12);
  imageName('/usr/lib/dyld', 20);
  image32(0xc);
  image32(56);
  image32(24);
  image32(0);
  image32(0x10000);
  image32(0x10000);
  imageName('/usr/lib/libSystem.B.dylib', 32);

  image32(0x32);
  image32(24);
  image32(1);
  image32(0xb0000);
  image32(0x1a0000);
  image32(0);

  int hash = 0x811c9dc5;
  int h = 0;
  while (h < machineCode.length) {
    hash = ((hash ^ machineCode[h]) * 0x01000193) & 0xffffffff;
    h = h + 1;
  }
  image32(0x1b);
  image32(24);
  image32(hash);
  image32((hash * 0x01000193) & 0xffffffff);
  image32((hash ^ payloadEnd) & 0xffffffff);
  image32((hash ^ (constants.globalBytes ~/ 8)) & 0xffffffff);

  image32(0x80000028);
  image32(24);
  image64(codeOffset);
  image64(0);
  image32(0x2);
  image32(24);
  image32(textSize);
  image32(0);
  image32(textSize);
  image32(1);
  image32(0xb);
  image32(80);
  imageZeros(72);
  image32(0x80000022);
  image32(48);
  imageZeros(40);
  int signatureCommand = image.length;
  image32(0x1d);
  image32(16);
  image32(0);
  image32(0);
  imagePatch32(20, image.length - 32);
  imageZeros(codeOffset - image.length);
  int instruction = 0;
  while (instruction < machineCode.length) {
    image32(machineCode[instruction]);
    instruction = instruction + 1;
  }
  imageZeros(constantOffset - image.length);
  imageConstants(constants, codeOffset, dataBase - base);
  imageZeros(textSize + 16 - image.length);
  signMachO(image, signatureCommand, linkeditCommand, textSize, 1);
  return image;
}

void image16(int value) {
  image.add(value & 255);
  image.add((value >> 8) & 255);
}

void imageElfSegment(
  int type,
  int flags,
  int offset,
  int address,
  int fileSize,
  int memorySize,
  int alignment,
) {
  image32(type);
  image32(flags);
  image64(offset);
  image64(address);
  image64(address);
  image64(fileSize);
  image64(memorySize);
  image64(alignment);
}

List<int> createElfExecutable() {
  int base = 0x400000;
  int codeOffset = 0x1000;
  int constantOffset = alignImage(codeOffset + machineCode.length * 4, 8);
  ConstantLayout constants = layoutConstants(constantOffset);
  int payloadEnd = constants.end;
  int dataOffset = alignImage(payloadEnd, 4096);
  int dataBase = base + dataOffset;
  int dataSize = alignImage(constants.globalBytes, 4096);
  int site = 0;
  while (site < addressSites.length) {
    int target = 0;
    if (addressKinds[site] == 0) {
      target = base + constants.stringOffsets[addressTargets[site]];
    } else if (addressKinds[site] == 1) {
      target = dataBase + constants.globalOffsets[addressTargets[site]];
    } else if (addressKinds[site] == 2) {
      target = base + constants.descriptorOffsets[addressTargets[site]];
    } else if (addressKinds[site] == 3) {
      target = base + constants.metadataOffset;
    } else if (addressKinds[site] == 5) {
      target = base + constants.dataOffsets[addressTargets[site]];
    } else if (addressKinds[site] == 6) {
      target = base + constants.callableOffsets[addressTargets[site]];
    } else {
      target = base + constants.typeOffsets[addressTargets[site]];
    }
    int word = addressSites[site];
    int pc = base + codeOffset + word * 4;
    int pages = ((target >> 12) - (pc >> 12)) & 0x1fffff;
    machineCode[word] = 0x90000000 | ((pages & 3) << 29) | ((pages >> 2) << 5);
    machineCode[word + 1] = 0x91000000 | ((target & 0xfff) << 10);
    site = site + 1;
  }
  image = <int>[];
  image.add(127);
  imageName('ELF', 3);
  image.add(2);
  image.add(1);
  image.add(1);
  imageZeros(9);
  image16(2);
  image16(183);
  image32(1);
  image64(base + codeOffset);
  image64(64);
  image64(0);
  image32(0);
  image16(64);
  image16(56);
  image16(3);
  image16(0);
  image16(0);
  image16(0);
  imageElfSegment(1, 5, 0, base, payloadEnd, payloadEnd, 4096);
  imageElfSegment(1, 6, dataOffset, dataBase, 0, dataSize, 4096);
  imageElfSegment(0x6474e551, 6, 0, 0, 0, 0, 16);
  imageZeros(codeOffset - image.length);
  int instruction = 0;
  while (instruction < machineCode.length) {
    image32(machineCode[instruction]);
    instruction = instruction + 1;
  }
  imageZeros(constantOffset - image.length);
  imageConstants(constants, codeOffset, dataBase - base);
  imageZeros(dataOffset - image.length);
  return image;
}

List<int> createExecutable() {
  if (targetOS == 1) return createElfExecutable();
  return createMachOExecutable();
}

void imageDescriptor(
  int id,
  int size,
  int fields,
  int refBitmap,
  int kind,
  int taggedBitmap,
  int name,
  int toString,
) {
  image64(id);
  image64(size);
  image64(fields);
  image64(refBitmap);
  image64(kind);
  image64(taggedBitmap);
  image64(name);
  image64(toString);
}

int imageTypeKind(int kind) {
  if (kind == tVoid) return typeKindVoid;
  if (kind == tInt) return typeKindInt;
  if (kind == tString) return typeKindString;
  if (kind == tBool) return typeKindBool;
  if (kind == tPointer) return typeKindPointer;
  if (kind == tDynamic) return typeKindDynamic;
  if (kind == tNull) return typeKindNull;
  if (kind == tObject) return typeKindObject;
  if (kind == tNum) return typeKindNum;
  if (kind == tNever) return typeKindNever;
  if (kind == tFunction || kind == kFunction) return typeKindFunction;
  if (kind == kNullable) return typeKindNullable;
  if (kind == kList) return typeKindList;
  return typeKindClass;
}

void imageBitmap(List<int> words, int count) {
  var i = 0;
  while (i < count) {
    var word = 0;
    if (i < words.length) word = words[i];
    image64(word);
    i++;
  }
}

void imageMetadataReference(ConstantLayout layout, int feature, int target) {
  var displacement = 0;
  if ((layout.metadataFeatures & feature) != 0 && target >= 0) {
    displacement = target - layout.metadataOffset;
  }
  image64(displacement);
}

void imageRootTable(ConstantLayout layout, int codeOffset, int dataBaseOffset) {
  if (layout.rootTableOffset < 0) return;
  imageZeros(layout.rootTableOffset - image.length);
  image64(emittedRootMaps.length);
  var calls = 0;
  if (layout.rootCallsOffset >= 0) {
    calls = layout.rootCallsOffset - layout.rootTableOffset;
  }
  image64(calls);
  image64(layout.globalRoots.length);
  var globals = 0;
  if (layout.globalRootsOffset >= 0) {
    globals = layout.globalRootsOffset - layout.rootTableOffset;
  }
  image64(globals);
  var i = 0;
  while (i < emittedRootMaps.length) {
    var roots = emittedRootMaps[i];
    var record = layout.rootCallsOffset + i * rootCallBytes;
    image64(codeOffset + roots.returnOffset - record);
    var count = roots.offsets.length;
    if (roots.boundary) count = -1;
    image64(count);
    var slots = 0;
    if (layout.rootSlotOffsets[i] >= 0) {
      slots = layout.rootSlotOffsets[i] - record;
    }
    image64(slots);
    i++;
  }
  i = 0;
  while (i < emittedRootMaps.length) {
    if (layout.rootSlotOffsets[i] == image.length) {
      var roots = emittedRootMaps[i];
      var slot = 0;
      while (slot < roots.offsets.length) {
        image64(roots.offsets[slot]);
        image64(roots.kinds[slot]);
        slot++;
      }
    }
    i++;
  }
  i = 0;
  while (i < layout.globalRoots.length) {
    var global = layout.globalRoots[i];
    var record = layout.globalRootsOffset + i * globalRootBytes;
    image64(dataBaseOffset + layout.globalOffsets[global] - record);
    var kind = storageTagged;
    if (typeIsReference(globalTypes[global])) kind = storageRef;
    image64(kind);
    i++;
  }
}

void imageConstants(ConstantLayout layout, int codeOffset, int dataBaseOffset) {
  int stringIndex = 0;
  while (stringIndex < strings.length) {
    if (layout.stringOffsets[stringIndex] >= 0) {
      String value = strings[stringIndex];
      image64(
        layout.stringDescriptorOffset - layout.stringOffsets[stringIndex],
      );
      image64(objectStaticRelative);
      image64(value.length);
      int character = 0;
      while (character < value.length) {
        image16(value.codeUnitAt(character));
        character++;
      }
      imageZeros(alignImage(image.length, 8) - image.length);
    }
    stringIndex++;
  }
  int descriptor = 0;
  while (descriptor < classSizes.length) {
    if (layout.descriptorOffsets[descriptor] >= 0) {
      int name = 0;
      if (layout.classNameStrings[descriptor] >= 0) {
        name =
            layout.stringOffsets[layout.classNameStrings[descriptor]] -
            layout.descriptorOffsets[descriptor];
      }
      int callback = classToStringFunctions[descriptor];
      int toString = 0;
      if (callback >= 0 && armFunctionOffsets[callback] > 0) {
        toString =
            codeOffset +
            armFunctionOffsets[callback] * 4 -
            layout.descriptorOffsets[descriptor];
      }
      int references = 0;
      if (layout.refBitmapOffsets[descriptor] >= 0) {
        references =
            layout.refBitmapOffsets[descriptor] -
            layout.descriptorOffsets[descriptor];
      }
      int tagged = 0;
      if (layout.taggedBitmapOffsets[descriptor] >= 0) {
        tagged =
            layout.taggedBitmapOffsets[descriptor] -
            layout.descriptorOffsets[descriptor];
      }
      imageDescriptor(
        descriptor,
        classSizes[descriptor],
        (classSizes[descriptor] - objectHeaderBytes) ~/ 8,
        references,
        descriptorClass,
        tagged,
        name,
        toString,
      );
    }
    descriptor++;
  }
  if (layout.stringDescriptorOffset >= 0) {
    imageDescriptor(-1, stringDataOffset, -1, 0, descriptorString, 0, 0, 0);
  }
  if (layout.listDescriptorOffset >= 0) {
    imageDescriptor(-2, listInstanceBytes, 4, 0, descriptorList, 0, 0, 0);
    imageDescriptor(-3, arrayDataOffset, -1, 0, descriptorWordArray, 0, 0, 0);
    imageDescriptor(-4, arrayDataOffset, -1, 0, descriptorRefArray, 0, 0, 0);
  }
  if (layout.taggedArrayDescriptorOffset >= 0) {
    imageDescriptor(-6, arrayDataOffset, -1, 0, descriptorTaggedArray, 0, 0, 0);
  }
  if (layout.intBoxDescriptorOffset >= 0) {
    imageDescriptor(-5, objectHeaderBytes + 8, 1, 0, descriptorIntBox, 0, 0, 0);
  }
  if (layout.functionDescriptorOffset >= 0) {
    imageDescriptor(
      -7,
      functionInstanceBytes,
      0,
      0,
      descriptorFunction,
      0,
      0,
      0,
    );
  }
  descriptor = 0;
  while (descriptor < classSizes.length) {
    var fields = (classSizes[descriptor] - objectHeaderBytes) ~/ 8;
    var words = (fields + 63) ~/ 64;
    if (layout.refBitmapOffsets[descriptor] >= 0) {
      imageBitmap(classPointerMasks[descriptor], words);
    }
    if (layout.taggedBitmapOffsets[descriptor] >= 0) {
      imageBitmap(classTaggedMasks[descriptor], words);
    }
    descriptor++;
  }
  int typeIndex = 0;
  while (typeIndex < layout.typeOffsets.length) {
    int offset = layout.typeOffsets[typeIndex];
    if (offset >= 0) {
      var type = dartTypes[typeIndex];
      image64(imageTypeKind(type.kind));
      int argument = 0;
      if (type.kind == kList || type.kind == kNullable) {
        argument = layout.typeOffsets[type.argument] - offset;
      } else if (type.kind == kFunction) {
        argument = layout.signatureOffsets[type.argument] - offset;
      }
      image64(argument);
      int classOffset = 0;
      if (type.kind == kClass) {
        classOffset = layout.descriptorOffsets[type.argument] - offset;
      }
      image64(classOffset);
      int representation = storageWord;
      if (typeIsTagged(typeIndex) || typeIndex == tVoid) {
        representation = storageTagged;
      } else if (typeIsReference(typeIndex)) {
        representation = storageRef;
      }
      image64(representation);
    }
    typeIndex++;
  }
  var signatureIndex = 0;
  while (signatureIndex < layout.signatureOffsets.length) {
    var offset = layout.signatureOffsets[signatureIndex];
    if (offset >= 0) {
      var signature = functionSignatures[signatureIndex];
      image64(layout.typeOffsets[signature.result] - offset);
      image64(signature.required);
      image64(signature.parameters.length);
      var p = 0;
      while (p < signature.parameters.length) {
        image64(layout.typeOffsets[signature.parameters[p]] - image.length);
        p++;
      }
    }
    signatureIndex++;
  }
  if (layout.metadataOffset >= 0) {
    imageMetadataReference(
      layout,
      metadataStrings,
      layout.stringDescriptorOffset,
    );
    if (layout.metadataBytes > metadataStringDescriptorOffset + 8) {
      imageMetadataReference(
        layout,
        metadataLists,
        layout.listDescriptorOffset,
      );
      imageMetadataReference(
        layout,
        metadataLists,
        layout.wordArrayDescriptorOffset,
      );
      imageMetadataReference(
        layout,
        metadataLists,
        layout.refArrayDescriptorOffset,
      );
      imageMetadataReference(
        layout,
        metadataLists,
        layout.taggedArrayDescriptorOffset,
      );
    }
    if (layout.metadataBytes > metadataTaggedArrayDescriptorOffset + 8) {
      imageMetadataReference(
        layout,
        metadataValues,
        layout.intBoxDescriptorOffset,
      );
      imageMetadataReference(layout, metadataValues, layout.handleTypeOffset);
    }
    if (layout.metadataBytes > metadataHandleTypeOffset + 8) {
      imageMetadataReference(layout, metadataRoots, layout.rootTableOffset);
    }
  }
  imageRootTable(layout, codeOffset, dataBaseOffset);
  var list = 0;
  while (list < constantData.length) {
    var offset = layout.dataOffsets[list];
    if (offset >= 0) {
      imageZeros(offset - image.length);
      var data = constantData[list];
      image64(layout.typeOffsets[data.type] - offset);
      image64(data.values.length);
      var tagged =
          typeIsClass(data.type) || typeIsTagged(typeArgument(data.type));
      var i = 0;
      while (i < data.values.length) {
        var entry = image.length;
        var kind = data.kinds[i];
        var value = data.values[i];
        if (kind == typeKindString) {
          value = layout.stringOffsets[value] - entry;
        } else if (kind == typeKindList || kind == typeKindClass) {
          value = codeOffset + armFunctionOffsets[value] * 4 - entry;
        } else if (kind == typeKindFunction) {
          value = layout.callableOffsets[value] - entry;
        }
        if (tagged) image64(kind);
        image64(value);
        i++;
      }
    }
    list++;
  }
  var function = 0;
  while (function < layout.callableOffsets.length) {
    var offset = layout.callableOffsets[function];
    if (offset >= 0) {
      image64(layout.functionDescriptorOffset - offset);
      image64(objectStaticRelative);
      image64(layout.typeOffsets[functionValueType(function)] - offset);
      image64(
        codeOffset +
            armFunctionOffsets[functions[function].callableAdapter] * 4 -
            offset,
      );
    }
    function++;
  }
}
