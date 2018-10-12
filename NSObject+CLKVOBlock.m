//
//  NSObject+CLKVOBlock.m
//  KVODemo
//
//  Created by Apple on 2018/10/11.
//  Copyright © 2018年 chilim. All rights reserved.
//

#import "NSObject+CLKVOBlock.h"
#import <objc/runtime.h>
#import <objc/message.h>

///被观察类的子类名前缀
static NSString * const kCLKVOClassPrefix = @"CLObserver_";
///关联的被观察对象的子类
static NSString * const kCMkvoAssiociateObserver = @"CLAssiociateObserver";

@interface CLObserverInfoBlock : NSObject

@property (nonatomic, weak) NSObject *observer;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) CLObservingBlock blockHandle;

@end

@implementation CLObserverInfoBlock

- (instancetype)initWithObserver: (NSObject *)observer forKey: (NSString *)key observeHandler: (CLObservingBlock)handler
{
    if (self = [super init]) {
        
        _observer = observer;
        self.key = key;
        self.blockHandle = handler;
    }
    return self;
}

@end

@implementation NSObject (CLKVOBlock)

static void KVO_setter(id self, SEL _cmd, id newValue){
    NSString *setterName = NSStringFromSelector(_cmd);
    NSString *getterName = getterForSetter(setterName);
    if (!getterName) {
        @throw [NSException exceptionWithName: NSInvalidArgumentException reason: [NSString stringWithFormat: @"unrecognized selector sent to instance %p", self] userInfo: nil];
        return;
    }
    id oldValue = [self valueForKey:getterName];
    struct objc_super superClass = {
        .receiver = self,
        .super_class = class_getSuperclass(object_getClass(self))
    };
    
    [self willChangeValueForKey:getterName];
    void (*objc_msgSendSuperKVO)(void *, SEL, id) = (void *)objc_msgSendSuper;
    objc_msgSendSuperKVO(&superClass, _cmd, newValue);
    [self didChangeValueForKey:getterName];
    
    //获取所有监听回调对象进行回调
    NSMutableArray *observers = objc_getAssociatedObject(self, (__bridge const void *)kCMkvoAssiociateObserver);
    for (CLObserverInfoBlock *info in observers) {
        if ([info.key isEqualToString:getterName]) {
            dispatch_async(dispatch_queue_create(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                info.blockHandle(self, getterName, oldValue, newValue);
            });
        }
    }
}

static Class kvo_Class(id self)
{
    return class_getSuperclass(object_getClass(self));
}

//获取setter方法名
- (NSString *)getSetterString:(NSString *)key{
    if (key.length <= 0) {
        return nil;
    }
    //第一个字母大写
    NSString *firstStr = [[key substringToIndex:1] uppercaseString];
    NSString *leaveStr = [key substringFromIndex:1];
    return [NSString stringWithFormat:@"set%@%@:",firstStr,leaveStr];
}
//获取getter方法名
static NSString * getterForSetter(NSString * setter){
    if (setter.length <= 0 || ![setter hasPrefix: @"set"] || ![setter hasSuffix: @":"]) {
        
        return nil;
    }
    
    NSRange range = NSMakeRange(3, setter.length - 4);
    NSString * getter = [setter substringWithRange: range];
    
    NSString * firstString = [[getter substringToIndex: 1] lowercaseString];
    getter = [getter stringByReplacingCharactersInRange: NSMakeRange(0, 1) withString: firstString];
    
    return getter;
}

- (Class)createKVOClassWithOriginalClassName: (NSString *)className{
    NSString *kvoClassName = [kCLKVOClassPrefix stringByAppendingString:className];
    Class observedClass = NSClassFromString(kvoClassName);
    if (observedClass) {
        return observedClass;
    }
    //创建新的子类，并且类名为前缀+原类名
    Class originalClass = object_getClass(self);
    Class kvoClass = objc_allocateClassPair(originalClass, kvoClassName.UTF8String, 0);
    //获取监听对象的class方法实现代码，然后替换新建类的class实现
    Method classMethod = class_getInstanceMethod(originalClass, @selector(class));
    const char *types = method_getTypeEncoding(classMethod);
    class_addMethod(kvoClass, @selector(class), (IMP)kvo_Class, types);
    //将子类注册到runtime中
    objc_registerClassPair(kvoClass);
    return kvoClass;
    
}

- (BOOL)hasSelector: (SEL)selector
{
    Class observedClass = object_getClass(self);
    unsigned int methodCount = 0;
    Method * methodList = class_copyMethodList(observedClass, &methodCount);
    for (int i = 0; i < methodCount; i++) {
        
        SEL thisSelector = method_getName(methodList[i]);
        if (thisSelector == selector) {
            
            free(methodList);
            return YES;
        }
    }
    
    free(methodList);
    return NO;
}

- (void)cl_addObserver:(NSObject *)object forKey:(NSString *)key withBlock:(CLObservingBlock)observerBlock{
    //1、先获取类的setter方法
    //获取方法名称，方法选择器
    SEL setterSelector = NSSelectorFromString([self getSetterString:key]);
    //获取类的实例方法
    Method setterMethod = class_getInstanceMethod([self class], setterSelector);
    //如果没有实现setter方法就抛出异常
    if (!setterMethod) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"unrecognized selector sent to instance %@",self] userInfo:nil];
        return;
    }
    //获取被观察类的名称
    Class observedClass = object_getClass(self);
    NSString *className = NSStringFromClass(observedClass);
    
    //动态创建一个被观察类的子类，类名加一个前缀
    if (![className hasPrefix:kCLKVOClassPrefix]) {
        //将被观察类的isa指针指向其子类
        observedClass = [self createKVOClassWithOriginalClassName:className];
        object_setClass(self, observedClass);
    }
    if (![self hasSelector:setterSelector]) {
        const char *types = method_getTypeEncoding(setterMethod);
        //子类重写被观察父类的setter方法，并将方法添加到子类
        class_addMethod(observedClass, setterSelector, (IMP)KVO_setter, types);
    }
    //新增一个观察者类
    CLObserverInfoBlock *newObserverInfo = [[CLObserverInfoBlock alloc] initWithObserver:object forKey:key observeHandler:observerBlock];
    //关联一个数组保存观察者对象
    NSMutableArray * observers = objc_getAssociatedObject(self, (__bridge void *)kCMkvoAssiociateObserver);
    //如果数组为nil则新建一个数组，并且关联到被观察者对象
    if (!observers) {
        observers = [NSMutableArray array];
        objc_setAssociatedObject(self, (__bridge void *)kCMkvoAssiociateObserver, observers, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [observers addObject:newObserverInfo];
}

- (void)cl_removeObserver:(NSObject *)object forKey:(NSString *)key{
    NSMutableArray *observers = objc_getAssociatedObject(self, (__bridge void *)kCMkvoAssiociateObserver);
    CLObserverInfoBlock *observerInfoRemoved = nil;
    for (CLObserverInfoBlock *observerInfo in observers) {
        if (observerInfo.observer == object && [observerInfo.key isEqualToString:key]) {
            observerInfoRemoved = observerInfo;
            break;
        }
    }
    [observers removeObject:observerInfoRemoved];
}

@end
