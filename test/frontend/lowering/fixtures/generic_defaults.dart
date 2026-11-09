// Omitted dynamic invocation is exercised only by the host test's SDK oracle.
// This fixture contains supported declarations, tear-offs and explicit calls.
// ignore_for_file: use_primary_constructors, unnecessary_type_name_in_constructor

String implicitBound<T>() => '$T';
String explicitNullableBound<T extends Object?>() => '$T';
String numBound<T extends num>() => '$T';
String dependentBounds<T extends num, U extends List<T>>() => '$T|$U';
String reorderedBounds<T extends List<U>, U extends num>() => '$T|$U';

class RecursiveBound<T extends RecursiveBound<T>> {}

String recursiveBound<T extends RecursiveBound<T>>() => '$T';
String contravariantBound<T extends void Function(T)>() => '$T';
String mixedBound<T extends T Function(T)>() => '$T';

class DefaultOwner<T> {
  String method<U extends T>() => '$T|$U';

  Function local() {
    String localDefault<U extends T>() => '$T|$U';
    return localDefault;
  }

  Function anonymous() =>
      <U extends T>() => '$T|$U';

  Function nested<V extends T>() {
    String nestedDefault<U extends V>() => '$T|$V|$U';
    return nestedDefault;
  }
}

class DefaultConstruct<T extends num> {
  DefaultConstruct();
}

class DefaultBox<T> {
  DefaultBox();
}

typedef DefaultAlias<U extends int> = DefaultConstruct<U>;
typedef DefaultListAlias<U extends num> = DefaultBox<List<U>>;

Function methodTearoff() => DefaultOwner<int>().method;
Function constructorTearoff() => DefaultConstruct.new;
Function aliasTearoff() => DefaultAlias.new;
Function listAliasTearoff() => DefaultListAlias.new;
Function mapEntryTearoff() => MapEntry.new;

const savedConstructor = DefaultConstruct.new;
const savedAlias = DefaultAlias.new;
const savedListAlias = DefaultListAlias.new;
const savedMapEntry = MapEntry.new;

Function constantConstructorTearoff() => savedConstructor;
Function constantAliasTearoff() => savedAlias;
Function constantListAliasTearoff() => savedListAlias;
Function constantMapEntryTearoff() => savedMapEntry;

String explicitApplications() =>
    '${implicitBound<String>()}|${explicitNullableBound<int>()}|'
    '${numBound<int>()}|${dependentBounds<int, List<int>>()}|'
    '${reorderedBounds<List<int>, int>()}|${DefaultOwner<int>().method<int>()}';
