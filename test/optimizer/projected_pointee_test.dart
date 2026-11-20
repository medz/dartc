import 'dart:ffi';
import 'package:dartc/src/optimizer/flow_state.dart';
import 'package:dartc/src/optimizer/flow_value.dart';
import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/optimizer.dart';
import 'package:dartc/target.dart';
import 'package:test/test.dart';

final class _Layout() implements FlowMemoryLayout {
  @override
  final nativeLayout = NativeLayout(Target.host());
  @override
  ObjectLayout objectLayout(ClassType type) => ObjectLayout([.word]);
}

void main() {
  final box = ClassType(null,'Owner');
  final field = InstanceField(box,'location',.integer);
  final width = NativeScalarType(Int64);
  final graph = IrProgram([IrClass(box,[field])],[]);
  const zero=Constant.integer(0);
  final origin=FunctionTarget(null,'reserve',.integer,[]);
  final sequence=Object();
  FlowValue n(int x)=>FlowValue.constant(Constant.integer(x));
  final backing=FlowObject(DirectCall(origin,[]),sequence);
  final tail=FlowObject(DirectCall(origin,[]),sequence);
  FlowValue pointer(FlowObject x)=> FlowValue.address(FlowAddress(FlowRegion(x),0));
  FlowResult run(FlowState s,Instruction op,List<FlowValue> args) => s.transfer(
      op,args,allocate:(i)=>FlowObject(i,sequence),repeated:false,
      invoke:(_,_,_)=>throw StateError('invoke'),call:(_,_,_)=>throw StateError('call'))!;
  for(final exposed in [false,true]) {
    test('scoped raw aliases carry transitively referenced native bytes exposed=$exposed',(){
      var state=FlowState(graph,memoryLayout:_Layout())
        .allocateMemory(backing,n(16),repeated:false).normal!
        .allocateMemory(tail,n(16),repeated:false).normal!;
      final create=NewPayload(box,zero);
      final result=run(state,create,[n(0)]);
      final owner=result.value.objects.single;
      state=run(result.normal!,StoreField(field,create,zero),[result.value,pointer(backing)]).normal!;
      state=run(state,StoreNative(zero,width,zero),[pointer(backing),pointer(tail)]).normal!;
      state=run(state,StoreNative(zero,width,zero),[pointer(tail),n(1009)]).normal!;
      if(exposed) state.recordEscape([result.value]);
      final access=(globals:<GlobalVariable>{},fields:<InstanceField>{},data:<NativeData>{},modules:<ModuleObject>{},
        context:false,cells:false,memory:true,exposed:false,writes:true,rawWrites:false);
      final external=state.project([FlowValue.unknown(box,external:true)],access:access);
      if(!exposed) {
        expect(external.containsObject(owner),isFalse);
        expect(external.containsObject(backing),isFalse);
      }
      final actual=state.project([FlowValue.unknown(.integer)],access:access);
      expect(actual.containsObject(owner),isTrue);
      final throughField=actual.storedFieldOf(owner,field)!;
      expect(throughField.addresses.single.base,FlowRegion(backing));
      final word=run(actual,LoadNative(zero,width),[throughField]).value;
      expect(word.addresses.map((p)=>p.base),contains(FlowRegion(tail)));
      expect(run(actual,LoadNative(zero,width),[word]).value.integers?.constant,1009);
    });
  }
}
