# 普通 extension 访问

在声明与直接方法调用的 receiver-first 静态 ABI 上，getter、setter、索引和运算符复用现有调用适配器，不增加 IR 指令或伪造接收者类。

## 已验证范围

- 隐式选择、显式 override、词法 class/extension 接收者和闭包；保留静态视图与泛型替换。
- getter、setter、setter-only 属性、`[]`/`[]=`、一元/二元运算符、复合赋值、`??=`、前后缀增减。
- 索引更新分别在读取和写入时检查 key 类型；`??=` 的非空结果不执行 setter key 检查。
- 空感知访问和级联跳过后续索引、getter、右值、运算符和 setter。
- getter 返回函数的调用先执行 getter，再计算调用实参；这与普通虚方法查找路径分开。
- 对象模式 extension getter，包括通配字段和候选分支缓存；关系模式包括可空接收者。静态 extension 调用的缓存键包含声明和结构化类型实参，避免不同选择错误共享结果。

[SDK 差分样本](../test/lowering/fixtures/extension_access.dart)覆盖结果、异常和副作用；[测试](../test/lowering/extension_access_test.dart)单独标明下述规范顺序检查。

## 赋值表达式值的已知差异

`final result = receiver().property = rhs()` 在选中普通 extension setter 时，IR 采用接收者、右值、setter 的顺序。Dart SDK 3.13.7 JIT 与 AOT 的独立实测却为右值、接收者、setter；显式 override 和直接表达式语句的观察结果又不同。

采用 receiver-first 是对[规范草案](https://spec.dart.dev/DartLangSpecDraft.pdf) §17.20、§13.2、§13.1 的分析结论；不是对 SDK 实测结果的描述。对照 [CFE 隐式路径](https://github.com/dart-lang/sdk/blob/3.13.7/pkg/front_end/lib/src/type_inference/inference_visitor_base.dart#L4550-L4580)和[显式路径](https://github.com/dart-lang/sdk/blob/3.13.7/pkg/front_end/lib/src/type_inference/inference_visitor.dart#L1923-L1958)，接收者临时变量处理存在差别；其因果解释仍属分析推断，未见官方确认。

测试独立断言 IR 的 receiver-first 顺序，不要求未来 SDK 保留该重排，也不把此项列为逐项 SDK 一致。

显式索引赋值值 `return E(receiver())[key()] = rhs()` 同样有差异：SDK 3.13.7 JIT/AOT 实测为接收者、右值、索引；IR 按 §17.23 结合 §13.1/§17.15.2 的分析采用接收者、索引、右值。此项也使用独立规范预期测试，覆盖接收者、索引、右值的异常和动态类型失败，以及 finally，不要求未来 SDK 保持当前行为。[CFE 值上下文路径](https://github.com/dart-lang/sdk/blob/3.13.7/pkg/front_end/lib/src/type_inference/inference_visitor.dart#L10003-L10074)先缓存右值但未先缓存索引，与观察相符；这仍是分析推断。此差异结论仅限上述 SDK 的 JIT/AOT，不外推到 JS/Wasm 或复合赋值。

## 仍明确拒绝的范围

- instance 方法提取，包括对象模式的方法字段；隐式 extension `call` 调用。
- analyzer 14.7 拒绝部分 SDK 有效的显式泛型二元运算符：`E<int>(box) + 7` 中若形式参数为 extension 的 `T`，它仍可能按未替换的 `T` 报类型错误。
- analyzer 14.7 接受部分显式泛型一元表达式，却把声明的 `T` 留在结果及外围 record 的静态类型中。lowering 对可能逃出词法作用域的结果明确拒绝，而不猜测修复整棵 AST 的类型。
- 原有核心库 extension 和 extension type 边界不变。

这些不是完整运算符支持；[边界测试](../test/lowering/extension_boundaries_test.dart)保留相应最小用例。
