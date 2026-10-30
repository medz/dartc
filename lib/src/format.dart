import 'arm64.dart';
import 'x64.dart';
import 'code.dart';
import 'target.dart';
import 'constant_data.dart';
import 'constant_layout.dart';
import 'format/image.dart';
import 'format/elf.dart';
import 'format/macho.dart';
import 'frame.dart';
import 'ir.dart';
import 'layout.dart';
import 'root_map.dart';
import 'sign.dart';
import 'types.dart';

List<int> createMachOExecutable() {
  int base = 0x100000000;
  int dataBase = 0x110000000;
  int pageShift = targetX64 ? 12 : 14;
  int page = 1 << pageShift;
  int codeOffset = 0x1000;
  int constantOffset = alignImage(codeOffset + codeSize, 8);
  ConstantLayout constants = layoutConstants(constantOffset);
  int payloadEnd = constants.end;
  int textSize = alignImage(payloadEnd, page);
  int dataSize = alignImage(constants.globalBytes, page);
  imageRelocate(constants, base, dataBase, codeOffset);

  image = <int>[];
  image32(0xfeedfacf);
  image32(targetX64 ? 0x1000007 : 0x100000c);
  image32(targetX64 ? 3 : 0);
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
    codeSize,
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
  while (h < codeWords.length) {
    hash = ((hash ^ codeWords[h]) * 0x01000193) & 0xffffffff;
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
  imageWords(codeWords, codeSize);
  imageZeros(constantOffset - image.length);
  imageConstants(constants, codeOffset, dataBase - base);
  imageZeros(textSize + 16 - image.length);
  signMachO(image, signatureCommand, linkeditCommand, textSize, 1, pageShift);
  return image;
}

List<int> createElfExecutable() {
  int base = 0x400000;
  int codeOffset = 0x1000;
  int constantOffset = alignImage(codeOffset + codeSize, 8);
  ConstantLayout constants = layoutConstants(constantOffset);
  int payloadEnd = constants.end;
  int dataOffset = alignImage(payloadEnd, 4096);
  int dataBase = base + dataOffset;
  int dataSize = alignImage(constants.globalBytes, 4096);
  imageRelocate(constants, base, dataBase, codeOffset);
  image = <int>[];
  imageElfHeader(2, base + codeOffset, 64, 0, 3, 0, 0);
  imageElfSegment(1, 5, 0, base, payloadEnd, payloadEnd, 4096);
  imageElfSegment(1, 6, dataOffset, dataBase, 0, dataSize, 4096);
  imageElfSegment(0x6474e551, 6, 0, 0, 0, 0, 16);
  imageZeros(codeOffset - image.length);
  imageWords(codeWords, codeSize);
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
  int toString, [
  int errorStackTrace = 0,
]) {
  image64(id);
  image64(size);
  image64(fields);
  image64(refBitmap);
  image64(kind);
  image64(taggedBitmap);
  image64(name);
  image64(toString);
  image64(errorStackTrace);
}

int imageErrorStackTraceOffset(int owner) {
  while (true) {
    if (owner == coreErrorClass) return coreErrorStackTraceOffset;
    final parent = classSuperclasses[owner];
    if (!typeIsClass(parent)) return 0;
    owner = typeArgument(parent);
  }
}

int imageTypeKind(int kind) {
  if (kind == tVoid) return typeKindVoid;
  if (kind == tInt) return typeKindInt;
  if (kind == tDouble) return typeKindDouble;
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
  if (kind == kTypeParameter) return typeKindParameter;
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

void imageFrameTable(ConstantLayout layout, int codeOffset) {
  if (layout.frameTableOffset < 0) return;
  imageZeros(layout.frameTableOffset - image.length);
  image64(emittedFrames.length);
  image64(layout.frameDescriptorsOffset - layout.frameTableOffset);
  for (var i = 0; i < emittedFrames.length; i++) {
    final frame = emittedFrames[i];
    final record = layout.frameDescriptorsOffset + i * frameDescriptorBytes;
    image64(codeOffset + frame.start - record);
    image64(codeOffset + frame.end - record);
    image64(frame.bytes);
    image64(frame.savedOffset);
    image64(frame.savedMask);
    final name = layout.frameNameStrings[i];
    image64(name < 0 ? 0 : layout.stringOffsets[name] - record);
  }
}

void imageHandlerTable(ConstantLayout layout, int codeOffset) {
  if (layout.handlerTableOffset < 0) return;
  imageZeros(layout.handlerTableOffset - image.length);
  image64(emittedHandlers.length);
  image64(layout.handlerEntriesOffset - layout.handlerTableOffset);
  for (var i = 0; i < emittedHandlers.length; i++) {
    final handler = emittedHandlers[i];
    final record = layout.handlerEntriesOffset + i * handlerEntryBytes;
    image64(codeOffset + handler.returnOffset - record);
    image64(codeOffset + handler.landingOffset - record);
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
      if (callback >= 0 && functionOffsets[callback] > 0) {
        toString =
            codeOffset +
            functionOffsets[callback] -
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
        classTypeArgumentOffsets[descriptor] == 0
            ? descriptorClass
            : descriptorGenericClass,
        tagged,
        name,
        toString,
        imageErrorStackTraceOffset(descriptor),
      );
      if (classTypeArgumentOffsets[descriptor] != 0)
        image64(classTypeArgumentOffsets[descriptor]);
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
  if (layout.doubleBoxDescriptorOffset >= 0) {
    imageDescriptor(
      -11,
      objectHeaderBytes + 8,
      1,
      0,
      descriptorDoubleBox,
      0,
      0,
      0,
    );
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
  var functionDescriptor = 0;
  if (layout.typeDescriptorOffset >= 0) {
    imageDescriptor(-10, typeRefBytes, 4, 0, descriptorType, 0, 0, 0);
  }
  while (functionDescriptor < layout.closureDescriptors.length) {
    var captured = layout.closureDescriptors[functionDescriptor];
    if (captured != null) {
      var closure = functions[functionDescriptor].closureLayout!;
      var fields = closure.fieldTypes.length;
      imageDescriptor(
        closure.boundReceiver ? boundMethodClassId : -7,
        functionInstanceBytes + fields * 8,
        (functionInstanceBytes - objectHeaderBytes) ~/ 8 + fields,
        captured.referencesOffset < 0
            ? 0
            : captured.referencesOffset - captured.offset,
        descriptorFunction,
        captured.taggedOffset < 0 ? 0 : captured.taggedOffset - captured.offset,
        0,
        0,
      );
    }
    functionDescriptor++;
  }
  var cellType = 0;
  while (cellType < layout.captureCellDescriptors.length) {
    var captured = layout.captureCellDescriptors[cellType];
    if (captured != null) {
      imageDescriptor(
        captureCellClassId,
        captureCellInstanceBytes,
        1,
        captured.referencesOffset < 0
            ? 0
            : captured.referencesOffset - captured.offset,
        descriptorClass,
        captured.taggedOffset < 0 ? 0 : captured.taggedOffset - captured.offset,
        0,
        0,
      );
    }
    cellType++;
  }
  for (final captured in layout.lateCellDescriptors) {
    if (captured != null) {
      imageDescriptor(
        lateCellClassId,
        lateCellInstanceBytes,
        3,
        captured.referencesOffset < 0
            ? 0
            : captured.referencesOffset - captured.offset,
        descriptorClass,
        captured.taggedOffset < 0 ? 0 : captured.taggedOffset - captured.offset,
        0,
        0,
      );
    }
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
  for (var descriptors in <List<CaptureDescriptor?>>[
    layout.closureDescriptors,
    layout.captureCellDescriptors,
    layout.lateCellDescriptors,
  ]) {
    for (var captured in descriptors) {
      if (captured != null) {
        if (captured.referencesOffset >= 0)
          imageBitmap(captured.references, captured.references.length);
        if (captured.taggedOffset >= 0)
          imageBitmap(captured.tagged, captured.tagged.length);
      }
    }
  }
  int typeIndex = 0;
  while (typeIndex < layout.typeOffsets.length) {
    int offset = layout.typeOffsets[typeIndex];
    if (offset >= 0) {
      var type = dartTypes[typeIndex];
      image64(layout.typeDescriptorOffset - offset);
      image64(
        objectStaticRelative |
            (typeContainsParameters(typeIndex) ? objectTypeTemplate : 0) |
            (type.kind == kClass && type.arguments.isNotEmpty
                ? objectTypeArguments
                : 0),
      );
      image64(imageTypeKind(type.kind));
      int argument = 0;
      if (type.kind == kList || type.kind == kNullable) {
        argument = layout.typeOffsets[type.argument] - offset;
      } else if (type.kind == kTypeParameter) {
        argument = runtimeTypeParameterIndex(typeIndex);
      } else if (type.kind == kFunction) {
        argument = layout.signatureOffsets[type.argument] - offset;
      } else if (type.kind == kClass &&
          layout.classSubtypeOffsets[typeIndex] >= 0) {
        argument = layout.classSubtypeOffsets[typeIndex] - offset;
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
      if (type.kind == kClass && type.arguments.isNotEmpty) {
        image64(type.arguments.length);
        for (var i = 0; i < type.arguments.length; i++)
          image64(
            layout.typeOffsets[type.arguments[i]] -
                (offset + classTypeArgumentsOffset + i * 8),
          );
      }
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
      image64(signature.positional);
      var p = 0;
      while (p < signature.parameters.length) {
        image64(layout.typeOffsets[signature.parameters[p]] - image.length);
        p++;
      }
      for (var i = 0; i < signature.names.length; i++) {
        image64(
          layout.stringOffsets[internString(signature.names[i])] - image.length,
        );
        image64(signature.requiredNamed[i] ? 1 : 0);
      }
    }
    signatureIndex++;
  }
  for (var i = 0; i < layout.callShapeOffsets.length; i++) {
    if (layout.callShapeOffsets[i] < 0) continue;
    final shape = callShapes[i];
    image64(shape.positional);
    image64(shape.names.length);
    for (final name in shape.names)
      image64(layout.stringOffsets[internString(name)] - image.length);
  }
  for (final subtypes in layout.classSubtypes) {
    if (subtypes.isEmpty) continue;
    image64(subtypes.length);
    for (final owner in subtypes)
      image64(layout.descriptorOffsets[owner] - image.length);
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
    if (layout.metadataBytes > metadataRootTableOffset + 8) {
      imageMetadataReference(
        layout,
        metadataValues,
        layout.doubleBoxDescriptorOffset,
      );
    }
    if (layout.metadataBytes > metadataDoubleBoxDescriptorOffset + 8)
      imageMetadataReference(layout, metadataFrames, layout.frameTableOffset);
    if (layout.metadataBytes > metadataFrameTableOffset + 8)
      imageMetadataReference(
        layout,
        metadataHandlers,
        layout.handlerTableOffset,
      );
  }
  imageRootTable(layout, codeOffset, dataBaseOffset);
  imageFrameTable(layout, codeOffset);
  imageHandlerTable(layout, codeOffset);
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
          value = codeOffset + functionOffsets[value] - entry;
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
            functionOffsets[functions[function].callableAdapter] -
            offset,
      );
    }
    function++;
  }
}

void imageRelocate(
  ConstantLayout constants,
  int base,
  int dataBase,
  int codeOffset,
) {
  for (final address in codeAddresses) {
    int target = 0;
    if (address.kind == 0) {
      target = base + constants.stringOffsets[address.target];
    } else if (address.kind == 1) {
      target = dataBase + constants.globalOffsets[address.target];
    } else if (address.kind == 2) {
      target = base + constants.descriptorOffsets[address.target];
    } else if (address.kind == 3) {
      target = base + constants.metadataOffset;
    } else if (address.kind == 5) {
      target = base + constants.dataOffsets[address.target];
    } else if (address.kind == 6) {
      target = base + constants.callableOffsets[address.target];
    } else if (address.kind == 7) {
      target = base + constants.closureDescriptors[address.target]!.offset;
    } else if (address.kind == 8) {
      target = base + constants.captureCellDescriptors[address.target]!.offset;
    } else if (address.kind == 11) {
      target = base + constants.callShapeOffsets[address.target];
    } else if (address.kind == 10) {
      target = base + constants.lateCellDescriptors[address.target]!.offset;
    } else {
      target = base + constants.typeOffsets[address.target];
    }
    final offset = address.offset;
    if (targetX64)
      xPatchRelative(offset, target - base - codeOffset);
    else
      armPatchAddress(offset, base + codeOffset + offset, target);
  }
}
