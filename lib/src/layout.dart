// Shared compiler/runtime object layout. Offsets are bytes.
const int runtimeAbiVersion = 7;
const int objectHeaderBytes = 16;
const int objectFlagsOffset = 8;
// Static objects store a descriptor displacement relative to their own address.
const int objectStaticRelative = 1;
const int objectListFixed = 2;
const int objectListReadOnly = 4;
const int stringLengthOffset = 16;
const int stringDataOffset = 24;

const int classDescriptorBytes = 64;
const int descriptorSizeOffset = 8;
const int descriptorKindOffset = 32;
const int descriptorTaggedMaskOffset = 40;
const int descriptorNameOffset = 48;
const int descriptorToStringOffset = 56;
const int descriptorClass = 0;
const int descriptorString = 1;
const int metadataStringDescriptorOffset = 0;

const int listLengthOffset = 16;
const int listCapacityOffset = 24;
const int listBackingOffset = 32;
const int listTypeOffset = 40;
const int listInstanceBytes = 48;
const int arrayLengthOffset = 16;
const int arrayDataOffset = 24;
// Compact constant-list metadata stores displacements from each record/entry.
const int constantListTypeOffset = 0;
const int constantListLengthOffset = 8;
const int constantListDataOffset = 16;
const int constantListTaggedEntryBytes = 16;
const int descriptorList = 2;
const int descriptorWordArray = 3;
const int descriptorRefArray = 4;
const int descriptorIntBox = 5;
const int descriptorTaggedArray = 6;
const int metadataListDescriptorOffset = 8;
const int metadataWordArrayDescriptorOffset = 16;
const int metadataRefArrayDescriptorOffset = 24;
const int metadataTaggedArrayDescriptorOffset = 32;
const int metadataIntBoxDescriptorOffset = 40;
const int metadataHandleTypeOffset = 48;

const int metadataStrings = 1;
const int metadataLists = 2;
const int metadataValues = 4;

// TypeRefs are native metadata records, separate from managed Dart Type objects.
const int typeRefBytes = 32;
const int typeKindOffset = 0;
const int typeArgumentOffset = 8;
const int typeClassOffset = 16;
const int typeValueRepOffset = 24;
const int typeKindVoid = 0;
const int typeKindInt = 1;
const int typeKindString = 2;
const int typeKindBool = 3;
const int typeKindPointer = 4;
const int typeKindList = 5;
const int typeKindClass = 6;
const int typeKindDynamic = 7;
const int typeKindNull = 8;
const int typeKindObject = 9;
const int typeKindNullable = 10;
const int typeKindNum = 11;
const int storageWord = 0;
const int storageRef = 1;
const int storageTagged = 2;
const int valueFalse = 2;
const int valueTrue = 4;
