# 变量

本页说明变量绑定、赋值和初始化，对应主规范 §8 及空安全规则。[状态与阶段含义](README.md#如何读矩阵)适用于下表；语义分析 API 当前未提供，正文的静态检查指 CLI 编译管线。

## 特性支持

| 特性 | 语法解析 | 语义分析 API | 编译/运行 | 使用限制 |
| --- | --- | --- | --- | --- |
| 显式类型、`var`、多变量声明 | 支持 | 未支持 | 部分 | 类型与推断限于[当前类型模型](types.md)。 |
| 顶层、静态、实例和局部变量 | 支持 | 未支持 | 部分 | 字段推断及初始化形式不完整。 |
| 局部遮蔽、捕获、声明前引用 | — | 未支持 | 部分 | 无前向互递归；完整闭包流规则仍缺。 |
| 通配变量 `_` | 支持 | 未支持 | 部分 | CLI 从 3.7 起不绑定局部/参数 `_`；不适用于字段和库变量。 |
| 确定赋值与确定未赋值 | — | 未支持 | 部分 | 非空类型引起的死边从 3.9 起参与合流。 |
| 局部 `final` 首次赋值 | 支持 | 未支持 | 部分 | 非 late 的捕获 final 不能在子函数中赋值。 |
| 库级/字段 `final` 与隐式访问器 | 支持 | 未支持 | 部分 | 只读存储可配显式 setter；完整构造初始化规则仍缺。 |
| `const` 与常量对象 | 支持 | 未支持 | 部分 | 支持标量、List、部分类实例及常量运算，不含完整常量语言。 |
| `late`、`late final` | 支持 | 未支持 | 部分 | 泛型类 late 字段、可捕获 LateInitializationError、异步规则仍缺。 |
| 库变量和静态字段惰性初始化 | — | 未支持 | 部分 | 赋值可跳过初始化器；初始化重入见下文。 |
| 模式变量声明与赋值 | 支持 | 未支持 | 部分 | 详见[模式](patterns.md)，Map/record 解构未支持。 |

## 声明语法

```dart
int count = 1, limit = 3;
final values = <int>[1, 2];
const defaults = <int>[1, 2];
late int cached = count + 1;
```

`parseCompilationUnit` 解析顶层变量与字段，`parseStatement` 解析局部声明，循环头可包含普通或模式声明。语法树保留元数据、`late`、`var`/`final`/`const`、共享类型和各变量的初始化式；顶层和字段还保留相应的 `external`、`static`、`abstract`、`covariant` 等修饰符。它不推断类型、不绑定名称、不检查常量资格或初始化时序；保留修饰符不代表该位置可编译。

## 绑定与通配变量

局部变量与局部函数共用词法名称检查。允许内层遮蔽，拒绝同一作用域重复声明；局部值可遮蔽同名类型和导入前缀。函数体内声明不影响签名的名称查找。

局部名字在整个作用域内预先确定，因此声明前读取是错误，不会退回同名全局变量。捕获按原声明绑定，不按调用时同名变量重新查找。局部函数名只读，可在自身函数体中递归，但不能前向互递归。

文件版本从 3.7 起，局部变量和参数 `_` 不引入可读取绑定，可以重复。查找仍可能得到同名库声明。此前 `_` 是普通局部名，参与遮蔽和重复检查。字段及库变量不会变成通配变量；模式 `_` 从模式特性的 3.0 起就是通配符。

## 初始化与确定赋值

```dart
int choose(bool flag) {
  final int result;
  if (flag) {
    result = 1;
  } else {
    result = 2;
  }
  return result;
}
```

CLI 分别跟踪“可以读取”和“允许 final 首次赋值”的事实。互斥分支可以分别首次赋值；重复写、增减、可能重复的循环外 final 写入被拒绝，循环体内每次新声明则可各自初始化。嵌套 RHS 求值后的写入也重新检查这些限制。

- 无初始化器的非 final 可空或 dynamic 局部变量取 null；未初始化的 final 即使可空也不能读取。
- 非 late 的库级/静态 final 与非空变量要求初始化。非 late 实例字段须由声明或受支持构造器初始化；只有工厂构造的类也不免除该义务。
- 读取采用提升类型，赋值按声明类型检查；赋值不会把存储类型永久改成提升类型。
- `??=` 同时要求可读和可写；不能因左值非空绕过 final 限制。RHS 可能被跳过，其中的写入不无条件建立赋值事实。
- 不可达代码仍检查局部分支中的读写。3.9 起才利用非空 null/is 分支和非空 `??`/`??=` 的死 RHS 合并赋值事实；旧版本仍使用 return、Never 和显式布尔控制流。
- 闭包读取继承声明点的已赋值事实，子函数的写入不使父函数自动成为已赋值。非 late 的捕获 final 不能在子函数中赋值。完整捕获流分析仍缺；模式及 try/finally 合流见[模式](patterns.md)和[语句](statements.md)。

## `final` 与 `const`

`final` 限制绑定重新赋值，不冻结对象；`const` 值还有常量资格、规范化身份与不可变性约束。

```dart
void main() {
  final mutable = <int>[1];
  mutable.add(2); // 可以修改对象，但不能重新给 mutable 赋值。
  const frozen = <int>[1];
  print(frozen); // 元素写入、改长和 clear 都会失败。
}
```

const 必须初始化。当前支持标量、嵌套常量 List、部分运算和[已支持的 const 类实例](classes.md#构造与初始化)，不等于完整常量语言。常量引用按作用域绑定并检查循环；局部函数可静态引用声明处此前可见的外层 const，包括聚合值和默认实参，不读取已结束调用的局部存储。局部函数引用本身不因此成为 const。

普通 final、有初始化器的 late final、const 没有隐式 setter。库变量、实例 final 字段及静态 final/const 字段可与显式 setter 配对，此时赋值调用 setter，不修改原只读存储。可变变量和无初始化器的 late final 已有隐式写入，不能再配同名显式 setter。静态字段不被子类继承。

## `late` 与首次读取初始化

```dart
int calls = 0;
int load() => ++calls;
late final int answer = load();

void main() {
  print(calls);  // 0。
  print(answer); // 1。
  print(answer); // 仍为 1，不再调用 load。
}
```

局部、库级、静态和非泛型实例 late 声明支持延迟初始化。赋值可跳过初始化器，null 是可以缓存的结果；正常返回后才缓存，抛出后下次读取可重试。局部初始化器有独立的闭包绑定，字段 late 初始化器可以访问 this；未使用的初始化器仍检查名称和类型。继承 late 字段及其 super 访问也在该子集内。

普通库变量、静态字段同样按首次读取初始化；有副作用的初始化器不会在未读取前执行。初始化可以重入：可变存储的初始化结果覆盖中途写入，final 在求值结束后检查内层调用是否已初始化。显式抛出保留已有写入，未完成的初始化可重试。

确定未赋值的局部 late 读取、确定已赋值的 late final 写入是静态错误；其他不确定情形在运行时检查。捕获共享状态，闭包可以初始化 late final。有初始化器的 late final 不提供隐式 setter。**当前 late 运行时失败仍退出进程，不能捕获 LateInitializationError。**

参数、catch 变量、循环头不能声明 late；const 构造器不能包含 late 字段。一般字段初始化器的类型依赖推断、泛型类 late 字段、完整闭包流分析和异步规则仍未完成。

## 规范依据

[主规范 §8](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[空安全与 late](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/feature-specification.md)、[通配变量](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.7/wildcard-variables/feature-specification.md)。
