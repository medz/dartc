// ignore_for_file: dead_code, unnecessary_type_name_in_constructor
import 'dependency.dart' as dep;
part 'private_part.dart';

const unsafeMultihop = dep.selected;
const unsafeFoldedBoolean = dep.b;
const unsafeSelectedPublic = dep.publicSelected;
const unsafeList = [dep.selected];
const unsafeMap = {'value': dep.selected};
const unsafeRecord = (dep.selected,);
const unsafeDeadBranch = false ? #_unexecuted : #public;
const unsafeField = dep.FieldBox();
const unsafeInitializer = dep.InitializerBox();
const unsafeDefault = dep.DefaultBox(1);
const unsafeAssertion = dep.AssertionBox();
const unsafeSuper = dep.ChildBox();
const unsafeRedirect = dep.RedirectBox();
const unsafeFactory = dep.FactoryBox();
const unsafePart = fromPart;
const unsafeQualified = #_a.public;

const safeUnrelated = 3;
const safePublic = #public;
const safeConstructedPrivate = Symbol('_p');
const safeConstructedEquality = Symbol('_p') == Symbol('_p');
const safeQualified = #a._private;
const safeConstructor = dep.SafeBox();
const safeNullDefault = dep.SafeNullDefault();

const unsafeReferencedInitializer = dep.ReferencedInitializerBox();
const unsafeReferencedField = dep.ReferencedFieldBox();
const unsafeReferencedDefault = dep.ReferencedDefaultBox();
const unsafeSuperArgument = dep.SuperArgumentBox();
