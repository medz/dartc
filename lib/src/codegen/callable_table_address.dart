import 'package:dartc/ir.dart';

/// A read-only table of demanded entry addresses for a callable environment.
///
/// This is machine address binding only. Entries and their effects have already
/// been analyzed as ordinary IR; a stored, uncalled function has a null table.
typedef CallableTableAddress = FunctionEntryTableAddress;
