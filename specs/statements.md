# 语句

本页说明控制流、跳转、异常与清理，对应主规范 §18。[状态与阶段含义](README.md#如何读矩阵)适用于下表；语义分析 API 当前未提供，正文的赋值/可达性检查属于 CLI 编译管线。

## 特性支持

| 特性 | 语法解析 | 语义分析 API | 编译/运行 | 使用限制 |
| --- | --- | --- | --- | --- |
| 块、空语句、表达式语句 | 支持 | 未支持 | 部分 | 表达式自身仍受支持子集限制。 |
| 局部变量与同步非泛型局部函数 | 支持 | 未支持 | 部分 | 绑定、final/late、捕获见[变量](variables.md)和[函数](functions.md)。 |
| if/else、while、do、普通 for | 支持 | 未支持 | 部分 | 支持短路、部分流合并；完整流分析仍缺。 |
| for-in | 支持 | 未支持 | 部分 | 限 List；无一般 Iterable/Iterator 和可捕获并发修改错误。 |
| if-case、模式声明及循环头 | 支持 | 未支持 | 部分 | 不含 Map/record 解构，见[模式](patterns.md)。 |
| switch、守卫、共享 case、隐式 break | 支持 | 未支持 | 部分 | 按语言版本区分常量 case 和模式规则。 |
| 标签、break、continue | 支持 | 未支持 | 部分 | CLI 绑定目标；parser 不检查目标存在或种类。 |
| return 与正常完成检查 | 支持 | 未支持 | 部分 | 非空结果不能正常落空，生成器执行未支持。 |
| try/on/catch、rethrow、finally | 支持 | 未支持 | 部分 | 仅同步展开，自动错误未全部对象化。 |
| await for | 支持 | 未支持 | 未支持 | 仅异步函数体上下文可解析；无 Stream 暂停/取消。 |
| yield/yield* | 支持 | 未支持 | 未支持 | 仅生成器体上下文可解析；无惰性 Iterable/Stream 输出。 |
| assert | 支持 | 未支持 | 未支持 | 无断言启用模式或自动 AssertionError 抛出。 |

## 语句解析 API

`parseStatement(ScanResult)` 解析一个语句，包含必需的分号和括号。多条语句须放在块中；独立入口使用同步上下文。异步 await for 和生成器 yield/yield* 通过[函数体入口](functions.md#解析入口)解析。

parser 保留块与语句顺序、声明/模式、循环初始化和多条更新、可省略条件、case/标签、异常类型及 catch 参数。else 关联最近未完成的 if。缺失语句以零宽节点恢复，调用方须检查 hasErrors。它不绑定名称、标签和捕获，不检查类型、确定赋值、穷尽性或 rethrow 是否处于合法 catch 上下文。

## 分支、循环与跳转

块顺序执行并引入局部作用域；表达式语句可丢弃结果，但保留副作用和可能失败的操作。if 检查布尔条件并合并两支流事实，while/for 的可能写入撤销失效提升。for 支持声明或表达式初始化、可省略条件、多条更新；do 先执行体，continue 跳到条件。

```dart
int sum(List<int> values) {
  var result = 0;
  outer: for (final value in values) {
    if (value < 0) continue outer;
    result += value;
  }
  return result;
}
```

for 声明的闭包绑定每轮独立，更新前复制当前值；for-in 的声明变量也逐轮独立，使用外部已有变量则共享绑定。模式循环头共用[模式绑定规则](patterns.md#声明赋值与循环解构)。

for-in 当前按 List 长度与索引迭代，来源一次求值，dynamic 来源须为 List，逐元素检查类型。每次迭代步先检查初始长度，改长在下次取元素/判定结束前失败，break 后不再检查；替换元素或步间恢复原长度可继续。这同时适用于语句和集合。**长度失败仍终止进程，不能捕获 ConcurrentModificationError**，与 List.toString 的已支持错误对象不同。

标签支持嵌套查找、块 break 和循环 continue；switch case 标签只接受 continue，不能 break。重复/不可见 case 标签及错误目标被诊断。跨越 try/catch 的跳转执行对应 finally，在块内跳转不提前清理；case 跳转不重新匹配模式或守卫。

## switch 与返回

Dart 3 switch 语句支持当前模式、守卫及有限穷尽性，空 case 共享后续 body，非空 body 正常结束后隐式 break。旧文件按常量 case 解释、检查类型，除最后 body 外要求显式退出，只有 default 消除未匹配赋值路径。共享模式变量、标签入口和版本差异详见[模式](patterns.md#switch-语句与共享绑定)。

return 支持显式值、无值和构造器返回限制，结果检查见[函数](functions.md#参数默认值与返回)。Never 表达式终止正常路径，但后续源码仍作静态检查。空感知 List 元素、空 List<Never> 的迭代/展开可能正常完成，不能据此省略非空结果函数的返回。

## 同步异常与 finally

```dart
int recover() {
  try {
    throw StateError('failed');
  } on StateError catch (error, stack) {
    print(error);
    return 1;
  } finally {
    print('cleanup');
  }
}
```

throw 单次求值，支持直接、闭包、方法值调用的同步跨帧展开。on 处理器按源码顺序匹配当前类型系统支持的类型及类型参数；省略 on 时异常参数静态类型为 Object，轨迹参数为核心 StackTrace，两者 final，catch 有独立参数作用域。try 中可能写入的变量在 catch 入口撤销提升并保守合并赋值事实。固定旧草案省略 on 等价 dynamic 的描述须结合空安全，不能直接照用。

rethrow 在同一函数中使用词法最近 catch 的异常对象和原 StackTrace，保留身份。内层 catch 完成后恢复外层上下文，嵌套函数不能借用外围 catch；同级 finally 也没有 catch 参数或该 rethrow 上下文。

finally 覆盖正常结束、return、break、continue、throw/rethrow。返回值先求值并保存，清理中的新退出覆盖原完成方式；支持嵌套清理、catch 后清理及 case/标签跳转。**只适用于已经进入同步异常机制的失败**，不能把直接进程退出当成保证执行 finally。

流分析为 finally 使用 try 中任意位置可能抛出时的保守入口，因此 try 内赋值不保证 finally 中可读。正常结束后可继承 try 或 finally 的确定赋值，清理可能写入的变量不能保留失效提升。break/continue 的目标状态仍取跳转处事实，不追加 finally 赋值，例如 SDK 3.13.7 与 dartc 都不将下例视作已赋值：

```dart
int x;
while (true) {
  try {
    break;
  } finally {
    x = 1;
  }
}
// 此处读取 x 仍是静态错误。
```

异步/生成器展开、完整流分析及所有运行时失败的错误对象化未完成。

## 核心错误与异常对象

CLI 提供 Error、AssertionError、TypeError、ArgumentError、RangeError、IndexError、UnsupportedError、UnimplementedError、StateError、ConcurrentModificationError、Exception、FormatException、IntegerDivisionByZeroException 的当前构造和继承子集。显式 throw 这些对象走普通 catch/finally，不等于对应操作均会自动抛该对象。

| 自动失败来源 | 当前行为 |
| --- | --- |
| 已支持类型转换、动态 bool 条件、空断言、dynamic null throw、协变写入/入口 | 抛可捕获 TypeError；文案尚缺实际值、目标类型或参数名。 |
| 非有限数值转整数、非有限浮点整除 | 抛 UnsupportedError。 |
| 固定长度/只读 List 的已支持变更 | 抛 UnsupportedError，类型检查先于只读性和范围，失败不改列表。 |
| List 格式化回调改长 | 抛 ConcurrentModificationError，载荷保留实际列表。 |
| String.fromCharCodes 非法码点 | 抛 ArgumentError，保留原输入，详见[字符串 API](expressions.md#string-api-边界)。 |
| StringBuffer.writeCharCode 非法码点 | 抛 RangeError，原内容保持不变。 |
| 整数 ~/、%、remainder 零除 | 抛 IntegerDivisionByZeroException，普通 catch/finally 可处理，自身 stackTrace 不填充。 |
| List 范围、for-in 改长、late 初始化及模式检查失败 | 尚未统一生成对应错误对象，不能依赖可捕获或 finally。 |

ArgumentError 支持默认/value/notNull 构造和 checkNotNull。RangeError 支持默认/value/range、checkValueInInterval/checkValidRange/checkNotNegative；IndexError 支持 withLength/check。依赖一般动态 indexable.length 的 IndexError 默认构造、RangeError.index/checkValidIndex 未支持。Exception 是 abstract interface class，跨库限制同[类修饰符](classes.md#类修饰符枚举与元数据)。

Error.safeToString 不调用用户 toString，字符串转义，List/函数提供安全概要，不承诺 VM 内部类名。FormatException 保留 message/source/offset，并输出行、位置和有限片段。

实际 extends Error 的对象首次抛出时填充 Error.stackTrace，后续 throw/rethrow/throwWithStackTrace 不覆盖该字段；普通重复 throw 的 catch 轨迹仍来自本次抛出。子类 getter 覆写不改父存储，implements Error 不自动填充。指定轨迹只保证内容，不承诺 StackTrace 对象身份；同步轨迹文本范围见[库](libraries.md#stacktrace-api)。

## 规范依据

[主规范 §18](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[模式规范](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/patterns/feature-specification.md)、[流分析](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/flow-analysis.md#statements)、[Error API](https://api.dart.dev/stable/3.13.7/dart-core/Error-class.html)。
