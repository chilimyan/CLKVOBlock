//
//  NSObject+CLKVOBlock.h
//  KVODemo
//
//  Created by Apple on 2018/10/11.
//  Copyright © 2018年 chilim. All rights reserved.
//

//KVO实现原理
///当你观察一个对象时，一个新的类会动态被创建。这个类继承自该对象的原本的类，并重写了被观察属性的 setter 方法。自然，重写的 setter 方法会负责在调用原 setter方法之前和之后，通知所有观察对象值的更改。最后把这个对象的 isa 指针 ( isa 指针告诉 Runtime 系统这个对象的类是什么 ) 指向这个新创建的子类，对象就神奇的变成了新创建的子类的实例。原来，这个中间类，继承自原本的那个类。不仅如此，Apple 还重写了 -class 方法，企图欺骗我们这个类没有变，就是原本那个类。更具体的信息，去跑一下 Mike Ash 的那篇文章里的代码就能明白，这里就不再重复。


#import <Foundation/Foundation.h>

///Block回调
typedef void (^CLObservingBlock) (id observedObject, NSString *keyPath, NSString *oldValue, NSString *newValue);

@interface NSObject (CLKVOBlock)

///添加KVO
- (void)cl_addObserver:(NSObject *)object forKey:(NSString *)key withBlock:(CLObservingBlock)observerBlock;
 ///移除KVO
- (void)cl_removeObserver:(NSObject *)object forKey:(NSString *)key;

@end
