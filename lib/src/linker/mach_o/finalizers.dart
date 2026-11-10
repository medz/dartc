import 'package:dartc/assembler.dart';
import 'package:dartc/assembler/arm64.dart' as arm;
import 'package:dartc/assembler/x64.dart' as x64;
import 'package:dartc/object.dart';

const finalizerServices = {
  r'$dartc.mach_o.cxa_atexit': '___cxa_atexit',
  r'$dartc.mach_o.abort': '_abort',
};

/// Replaces terminator pointers with initializers registering their callbacks.
/// Legacy terminator arrays are not reliably invoked at unload by current dyld.
ObjectModule registerFinalizers(ObjectModule object) {
  final pointers =
      object.relocations
          .where((r) => object.sections[r.section].kind == .finalizers)
          .cast<AddressRelocation>()
          .toList()
        ..sort(
          (a, b) => a.section == b.section
              ? a.offset.compareTo(b.offset)
              : a.section.compareTo(b.section),
        );
  if (pointers.isEmpty) return object;
  final imports = [...object.imports];
  for (final name in finalizerServices.keys) {
    if (!imports.contains(name)) imports.add(name);
  }
  final symbolCount = object.symbols.length + pointers.length;
  final register = symbolCount + imports.indexOf(finalizerServices.keys.first);
  final abort = symbolCount + imports.indexOf(finalizerServices.keys.last);
  final code = <int>[], symbols = [...object.symbols];
  final references = <Relocation>[];
  for (final pointer in pointers) {
    final start = code.length;
    void fix(Fixup fixup, int symbol) => references.add(
      Relocation.instruction(
        object.sections.length,
        start + fixup.offset,
        fixup.encoding,
        symbol,
      ),
    );
    final List<int> body;
    if (object.target.architecture == .arm64) {
      final a = arm.Assembler();
      a
        ..addImmediate(.sp, .sp, -16)
        ..store(.x30, .sp, 0);
      fix(a.pageAddress(.x0), pointer.symbol);
      fix(a.addPageOffset(.x0, .x0), pointer.symbol);
      // dyld finalizes DSO tokens inside the unloaded executable ranges.
      a
        ..loadImmediate(.x1, 0)
        ..move(.x2, .x0);
      fix(a.call(), register);
      final success = a.label();
      a
        ..extendInteger(.x0, .x0, bytes: 4, signed: false)
        ..branchZero(.x0, success);
      fix(a.call(), abort);
      a
        ..bind(success)
        ..load(.x30, .sp, 0)
        ..addImmediate(.sp, .sp, 16)
        ..ret();
      body = a.finish();
    } else {
      final a = x64.Assembler();
      a.push(.rbp);
      fix(a.address(.rdi), pointer.symbol);
      a
        ..loadImmediate(.rsi, 0)
        ..move(.rdx, .rdi);
      fix(a.call(), register);
      final success = a.label();
      a
        ..extendInteger(.rax, .rax, bytes: 4, signed: false)
        ..test(.rax)
        ..jumpCondition(.equal, success);
      fix(a.call(), abort);
      a
        ..bind(success)
        ..pop(.rbp)
        ..ret();
      body = a.finish();
    }
    references.add(
      Relocation.address(pointer.section, pointer.offset, symbols.length),
    );
    symbols.add(
      Symbol(
        'register_finalizer',
        object.sections.length,
        start,
        body.length,
        binding: .local,
      ),
    );
    code.addAll(body);
  }
  for (final reference in object.relocations) {
    if (object.sections[reference.section].kind == .finalizers) continue;
    final symbol = reference.symbol < object.symbols.length
        ? reference.symbol
        : reference.symbol + pointers.length;
    references.add(switch (reference) {
      AddressRelocation() => Relocation.address(
        reference.section,
        reference.offset,
        symbol,
      ),
      InstructionRelocation() => Relocation.instruction(
        reference.section,
        reference.offset,
        reference.encoding,
        symbol,
        indirect: reference.indirect,
      ),
    });
  }
  return ObjectModule(
    object.target,
    [...object.sections, Section.code(code)],
    symbols,
    imports: imports,
    relocations: references,
  );
}
