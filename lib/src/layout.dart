// Shared compiler/runtime object layout. Offsets are bytes.
const int objectHeaderBytes = 16;
const int objectStaticRelative = 1;
const int stringLengthOffset = 16;
const int stringDataOffset = 24;

const int classDescriptorBytes = 40;
const int descriptorSizeOffset = 8;
const int descriptorKindOffset = 32;
const int descriptorClass = 0;
const int descriptorString = 1;
const int metadataStringDescriptorOffset = 0;
