import 'enum_private_storage.dart' as values;

String crossLibraryEnumStorage() =>
    '${values.alias.own}:${values.alias.name}:${values.record.$1.name}:'
    '${identical(values.nested[0], values.Code.first)}:'
    '${identical(values.nested[1], values.Code.third)}:'
    '${values.same}:${values.different}:'
    '${values.lookup[values.Code.first]}:${values.lookup[values.Code.third]}';
