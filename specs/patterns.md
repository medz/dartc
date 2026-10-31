# 模式、switch 与 if-case

本页说明 Dart 3 模式匹配、解构、守卫和穷尽性。[状态与阶段含义](README.md#如何读矩阵)适用于下表；语义分析 API 当前未提供，CLI 的绑定、匹配类型和覆盖检查不代表新 AST 已有公开分析器。

## 特性支持

| 特性 | 语法解析 | 语义分析 API | 编译/运行 | 使用限制 |
| --- | --- | --- | --- | --- |
| 常量、变量、类型、通配、括号模式 | 支持 | 未支持 | 部分 | 类型和常量限当前模型；模式 `_` 不引入绑定。 |
| 逻辑与/或、关系模式 | 支持 | 未支持 | 部分 | 用户关系运算符限非泛型类及有界参数；用户 ==/!= 未支持。 |
| cast、null-check、null-assert 模式 | 支持 | 未支持 | 部分 | cast/空断言失败无可捕获错误对象；null-check 失败只是不匹配。 |
| 对象模式、字段名推导 | 支持 | 未支持 | 部分 | 已有属性/方法值可读；动态/扩展成员、泛型父接口仍缺。 |
| List 模式及 rest | 支持 | 未支持 | 部分 | 支持嵌套与切片；一般 List 子类型覆写仍有限制。 |
| Map、record 模式 | 支持 | 未支持 | 未支持 | 没有解构、匹配缓存和空间运算。 |
| switch 表达式 | 支持 | 未支持 | 部分 | 从 3.0 起，不是常量表达式。 |
| 语句和 List 元素 if-case | 支持 | 未支持 | 部分 | 运行时 List 可用，Set/Map 与常量 if-case 未支持。 |
| 局部模式声明/赋值 | 支持 | 未支持 | 部分 | 对象/List 等子集，赋值仅限已有局部变量/参数。 |
| for/for-in 模式循环头 | 支持 | 未支持 | 部分 | for-in 限 List，每轮独立绑定；late 未支持。 |
| switch 语句、guard、共享 case | 支持 | 未支持 | 部分 | Dart 3 隐式 break；旧版常量 case 规则另见正文。 |
| bool/Null/Never/枚举穷尽性 | — | 未支持 | 部分 | 守卫与关系模式不贡献覆盖。 |
| 非泛型 sealed 层次穷尽性 | — | 未支持 | 部分 | 泛型父接口和完整解构字段空间仍缺。 |
| List 长度与对象属性空间覆盖 | — | 未支持 | 部分 | 有限长度联合/全属性覆盖，不是完整空间代数。 |
| 完整不可达 case 诊断 | — | 未支持 | 未支持 | 不可达臂仍检查名称、类型及其他静态义务。 |

## 模式解析 API

`parsePattern(ScanResult, context: PatternContext.matching)` 解析一个模式。`declaration` 用于外层已有 var/final 的声明，`assignment` 用于给已有变量赋值。裸名字保留为 IdentifierPattern，含义留给使用位置，不提前绑定为常量或声明。

parser 接受常量/点简写、变量、通配、关系、&&/||、括号、as/?/!、List/Map/record/对象模式，保留显式类型、rest 和省略名字段。连续一元后缀需要括号。缺失模式以零宽 MissingPattern 恢复；不求值常量、不推断字段名或类型、不检查穷尽性。

模式声明/赋值、语句/集合 if-case、模式循环头、switch 语句/表达式及 when 已接入相应文件/语句/表达式入口。**Map/record 可解析不表示 CLI 能匹配**。元数据、选择值、守卫和结果保留源码范围，调用方仍须检查 hasErrors。

## 匹配、守卫与绑定

```dart
int firstPositive(Object input) => switch (input) {
  [int first, ...] when first > 0 => first,
  _ => 0,
};

void show(Object input) {
  if (input case [int first, ...] when first > 0) {
    print(first);
  }
}
```

CLI 从 3.0 起支持 switch 表达式和 if-case。选择值只求一次，按源码顺序尝试模式、守卫、结果；匹配失败不执行守卫，守卫失败继续下一臂或进入 else。switch 各结果接受下行上下文，再合并结果类型并转换。if-case 的选择表达式不从模式获得下行上下文，模式变量仅在 guard/then 可见，then 可以修改非 final 变量或另声明同名变量。

常量模式将常量放在比较左侧；关系 RHS 必须是常量，按运算符参数上下文检查实际值类型。显式变量类型是声明类型，不隐式缩成选择值类型；无类型变量匹配 Null 时推为 dynamic。var/final/带类型的 `_` 都是通配模式，模式 `_` 从 3.0 起不绑定，不受普通通配变量 3.7 门槛影响。

&&/|| 保留优先级和短路。&& 禁止重复变量；|| 两侧须绑定同名、同 final 性质和同声明类型的变量，成功后表示共同绑定。as 检查后进入内部模式，? 对 null 匹配失败，! 对 null 失败；内部变量取检查后类型，但**cast/空断言模式检查失败仍可直接终止进程**，没有对应可捕获错误对象。

每个 switch 表达式臂先建立模式变量作用域再绑定模式、guard、结果，因此局部名可遮蔽模式中的类型/常量。as/when 不能作模式变量名或裸常量名。switch 表达式模式变量在 guard 和结果中只读，闭包也受限制；捕获保留本次匹配值，包括 guard 失败后逃逸的闭包。

if-case 的 guard 禁止普通赋值修改本 case 模式变量，包括 guard 内闭包；then 仍可改非 final 变量，guard 捕获必须观察后续修改，每次匹配有独立绑定。guard 可写普通外层变量，但写原选择变量后，后续模式仍匹配缓存值，不能继续提升已写变量。成功、失败、guard 失败分别合并流状态，全覆盖模式可建立确定赋值。

## 对象与 List 模式

对象模式不是构造器调用。支持命名类型、前缀和别名，显式或推断实参；可读字段、getter、方法值以及已有 String/List 属性可参与。成员按模式声明类型查找并检查私有性，重复字段、不可读成员及错误绑定在未使用分支也检查。`:var name`、`:final name` 及其一元包装可推导字段名。

省略 List、泛型类或别名实参时，按匹配值向下推导，保留外层参数身份；类参数按协变收约束，嵌套函数参数反转，重复约束合并，未约束参数按界实例化。上下文 C<U> 保留已绑定 U，匹配值本身是类型参数时不展开其上界来推断实参；类内匹配同一泛型类时使用新的推断身份。SDK 3.13.7 对 Null/Never 上下文不保留该约束，如 List<Null> 匹配 List(first: var value) 后 value 推导为 dynamic。泛型父接口代入、动态/扩展成员及完整约束求解仍缺。

List 模式支持显式元素类型、推导、嵌套、任意位置的单个 rest 及 rest 子模式。先检查 List 类型和必要长度，再按源码顺序匹配。匹配 rest 用 sublist 产生独立可增长列表，保留实际元素类型；无匹配 rest 不切片，`[...]` 不读长度或分配。

### 匹配读取快照

同一次 if-case/switch 匹配按根和访问路径共享首次读取，包含嵌套、逻辑组合和 guard 失败后的后续臂；不同路径即使指向同一对象也分别读取。首次读取保持源码顺序与短路，**对象通配符属性也调用 getter**；guard 不能刷新缓存，下一次执行匹配重新读取。

List 长度与对象 length 属性共用路径键；从首部索引、从尾部索引、rest 的首尾截取数量各自成键，即使实际下标相同也不合并。无类型 `_`、var _、final _ 及其括号形式不读取元素或生成 rest 切片，带类型通配符仍读取。这采用 SDK 3.13.7 比固定规范 identifier wildcard 更宽的调用省略范围。Map/record、扩展等调用键未提供。

## 穷尽性与不可达分支

switch 表达式在当前类型空间内检查覆盖，Never 可零臂。支持 bool、Null、可空类型及全覆盖变量/类型模式；可空性独立计算。守卫和关系模式不贡献穷尽性，`== true`/`== false`、`!= null` 不能替代对应常量/类型模式。不可达臂和未调用函数仍作静态检查，但完整不可达 case 诊断未提供。

- 对象模式仅在每个子模式覆盖完整属性类型时贡献类型覆盖，不能证明 `Box(flag: true)` 与 `Box(flag: false)` 的字段空间联合覆盖。
- List 模式在元素及 rest 子模式全覆盖时按长度区间联合，可识别 `[]` 加 `[_, ...]`，受限元素的完整空间运算未支持。
- 枚举按常量值序号覆盖，或模式取并集，guard 不计；可空枚举另需 null。嵌套对象/List 内的枚举常量不贡献覆盖。
- sealed 非泛型层次按同库直接子类型递归展开，开放分支须整体覆盖，枚举叶按值覆盖；支持菱形、nullable、有界参数、逻辑与/或和全属性对象模式。sealed 空层次可零臂；泛型层次、record 和完整字段空间分析仍缺。

SDK 3.13.7 CFE 不通过逻辑与合并 List 长度空间，例如 `[] || [_]` 和 `[_, ...] && [_, _, ...]` 两臂仍报非穷尽，`([] || [_, ...]) && List<int>()` 单臂也拒绝。dartc 保留该静态边界，运行时 && 正常匹配；固定空间规范定义交集，不能把当前拒绝解释为这些组合数学上不覆盖列表。

## 声明、赋值与循环解构

```dart
void main() {
  var [head, ...tail] = <int>[1, 2, 3];
  [head, ...tail] = <int>[4, 5];
  print(head); // 4。
  print(tail); // [5]。
}
```

从 3.0 起支持局部 var/final 模式声明、已有局部变量/参数的模式赋值，以及语句/List 元素 for/for-in 解构，复用对象、List、括号、逻辑与、cast 和空断言模式。支持元数据、上下文 schema、确定赋值、final 首次写入及逐轮捕获；RHS 一次求值，赋值表达式保留其值和类型。拒绝 refutable 模式、重复名、声明前引用、非局部赋值及赋值中的类型声明。late、Map/record、一般 Iterable 和失败错误对象仍缺。

显式类型提供下行 schema，未注解变量留未知项，List 子模式按最大下界合并，cast 不提供上下文，空断言提供可空上下文。dynamic 输入有隐式检查，其他输入须为所需类型子类型；解构不隐式提取 call，模式赋值不按元素类型提升目标变量。

**赋值当前非原子**：按 SDK 3.13.7 CFE 子模式顺序写回，`C(a: x, b: y) = value` 的 b getter 能看见新 x，后续空断言失败不撤销已写值。固定规范要求匹配完成后统一写回；当前不遵循该原子性描述，且失败后 catch 观察不受支持。

SDK 3.13.7 CFE/analyzer 允许 guard 中 `[x] = [value]` 修改本 case 变量（含闭包），但拒绝普通 `x = value`；dartc 采用该区别，固定规范没有说明此例外。对 `var ([a] && [List<int> b]) = [[]]`，CFE 使用共同 List<int> 元素上下文，analyzer 用 List<dynamic> 报错，dartc 采用 CFE 上下文。

## switch 语句与共享绑定

Dart 3 switch 语句支持模式/guard、空 case 共用 body、正常结束隐式 break 和 case 标签 continue。同一 body 的同名变量须在各入口有相同声明类型及 finality；guard 各自独立绑定，共享 body 使用新绑定，单 case 直接使用原绑定。缺失、不一致或带标签/default 的同名变量仍遮蔽外层，使用时才诊断，未使用可保留。

支持共享变量的 guard 提升合流、捕获与每次进入独立绑定。bool、Null、Never、枚举、sealed（含可空）要求穷尽，其他已支持类型非穷尽可正常结束；泛型 sealed/record/未实现模式不据此承诺可用。

case 标签 continue 直接入其非空 body，不重试模式/guard，即使标签未被引用也不能在该 body 用原 case 模式变量。标签入口撤销整个 switch 写集合涉及的提升和确定未赋值事实，其他 case 写入不使未初始化变量可读。跨 finally 跳转仍执行清理，普通循环 continue 和外层 switch break 保持各自目标。

小于 3.0 的文件将 case 解释为隐式常量表达式，包括算术、`_` 常量和 List 身份匹配；case 静态类型须是选择值类型子类型。最后 body 可正常结束，之前非空 body 须退出；只有 default 排除未匹配赋值路径。SDK 3.13.7 CFE/analyzer 也接受 2.19 文件的 when 并执行 guard，dartc 保留此参考行为，而非把模式语义全部用于旧文件。

## 其他使用限制与 SDK 差异

- 点简写常量模式用匹配值命名空间；关系模式的直接简写也跟随 SDK 3.13.7 扩大到全部关系运算，虽固定点简写规范只单列 ==/!=。double 匹配值的 `< .infinity` 可用，`< (.infinity)` 改用运算符参数 num 上下文并被拒绝；普通比较表达式不扩大此特例。
- 用户 `< <= > >=` 支持当前非泛型类及有界参数，经继承/接口分派；结果须可赋给 bool，dynamic 结果运行时检查。常量参数按实际值编译期检查，不因声明 dynamic 延后；CFE 对 dynamic 简写常量还可能转换到匹配值类型，dartc 跟随，analyzer 可不报错。用户 ==/!=、dynamic 用户方法分派和扩展运算符未支持。
- 字符串常量 `'=='`、`'<'`、`'when'`、`'as'` 仍是字符串，不按内容当运算符或模式关键字。
- SDK 3.13.7 CFE 接受 void 选择值及 var 绑定、void 关系常量，analyzer 报 use_of_void_result。dartc 采用 CFE，所得值仍受 void 消费限制。
- 固定文档列出 identifier pattern 的字段名推导，但 SDK 3.13.7 CFE 拒绝匹配中的 `C(:x)` 常量引用；dartc 也要求显式字段名或变量模式。
- 常量 List if-case 未支持，当前拒绝不表示已核实语言非法。SDK 3.13.7 CFE 对活跃和未执行 if-case 都可能内部错误，analyzer 对 bool 示例接受、非 bool 报错或涉及变量时异常退出，常量语义仍待确认。

## 规范依据

[模式特性规范](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/patterns/feature-specification.md)、[穷尽性](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/patterns/exhaustiveness.md)、[对象模式类型推断](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/patterns/feature-specification.md#L2118-L2141)。
