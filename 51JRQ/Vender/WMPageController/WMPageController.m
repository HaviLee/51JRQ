//
//  WMPageController.m
//  WMPageController
//
//  Created by Mark on 15/6/11.
//  Copyright (c) 2015年 yq. All rights reserved.
//

#import "WMPageController.h"
#import "LMDropdownView.h"
#import "AppDelegate.h"
#import "PYSearchViewController.h"
#import "TagsFilterTableViewCell.h"

NSString *const WMControllerDidAddToSuperViewNotification = @"WMControllerDidAddToSuperViewNotification";
NSString *const WMControllerDidFullyDisplayedNotification = @"WMControllerDidFullyDisplayedNotification";

static NSInteger const kWMUndefinedIndex = -1;
static NSInteger const kWMControllerCountUndefined = -1;
@interface WMPageController ()<UITableViewDelegate,UITableViewDataSource,LMDropdownViewDelegate,PYSearchViewControllerDelegate>
{
    CGFloat _viewHeight, _viewWidth, _viewX, _viewY, _targetX, _superviewHeight;
    BOOL    _hasInited, _shouldNotScroll, _isTabBarHidden;
    NSInteger _initializedIndex, _controllerConut, _markedSelectIndex;
}
@property (nonatomic, strong, readwrite) UIViewController *currentViewController;
// 用于记录子控制器view的frame，用于 scrollView 上的展示的位置
@property (nonatomic, strong) NSMutableArray *childViewFrames;
// 当前展示在屏幕上的控制器，方便在滚动的时候读取 (避免不必要计算)
@property (nonatomic, strong) NSMutableDictionary *displayVC;
// 用于记录销毁的viewController的位置 (如果它是某一种scrollView的Controller的话)
@property (nonatomic, strong) NSMutableDictionary *posRecords;
// 用于缓存加载过的控制器
@property (nonatomic, strong) NSCache *memCache;
@property (nonatomic, strong) NSMutableDictionary *backgroundCache;
// 收到内存警告的次数
@property (nonatomic, assign) int memoryWarningCount;
@property (nonatomic, readonly) NSInteger childControllersCount;
//
@property (strong, nonatomic) LMDropdownView *dropdownView;
@property (nonatomic, strong) UITableView *tagTableView;
    //测试数据
@property (nonatomic, strong) NSArray *allTags;
@property (nonatomic, strong) NSMutableArray *cellInfos;

@property (nonatomic, strong) UIView *buttonBackView;
@property (nonatomic, strong) UIView *backView;

@end

@implementation WMPageController

#pragma mark - Lazy Loading
- (NSMutableDictionary *)posRecords {
    if (_posRecords == nil) {
        _posRecords = [[NSMutableDictionary alloc] init];
    }
    return _posRecords;
}

- (NSMutableDictionary *)displayVC {
    if (_displayVC == nil) {
        _displayVC = [[NSMutableDictionary alloc] init];
    }
    return _displayVC;
}

- (NSMutableDictionary *)backgroundCache {
    if (_backgroundCache == nil) {
        _backgroundCache = [[NSMutableDictionary alloc] init];
    }
    return _backgroundCache;
}

#pragma mark - Public Methods

- (instancetype)initWithViewControllerClasses:(NSArray<Class> *)classes andTheirTitles:(NSArray<NSString *> *)titles {
    if (self = [super init]) {
        NSParameterAssert(classes.count == titles.count);
        _viewControllerClasses = [NSArray arrayWithArray:classes];
        _titles = [NSArray arrayWithArray:titles];

        [self wm_setup];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    if (self = [super initWithCoder:aDecoder]) {
        [self wm_setup];
    }
    return self;
}

- (instancetype)init {
    if (self = [super init]) {
        [self wm_setup];
    }
    return self;
}

- (void)setEdgesForExtendedLayout:(UIRectEdge)edgesForExtendedLayout {
    if (self.edgesForExtendedLayout == edgesForExtendedLayout) return;
    [super setEdgesForExtendedLayout:edgesForExtendedLayout];
    
    if (_hasInited) {
        _hasInited = NO;
        [self viewDidLayoutSubviews];
    }
}

- (void)forceLayoutSubviews {
    _hasInited = NO;
    [self viewDidLayoutSubviews];
}

- (void)setScrollEnable:(BOOL)scrollEnable {
    _scrollEnable = scrollEnable;
    
    if (!self.scrollView) return;
    self.scrollView.scrollEnabled = scrollEnable;
}

- (void)setProgressViewCornerRadius:(CGFloat)progressViewCornerRadius {
    _progressViewCornerRadius = progressViewCornerRadius;
    if (self.menuView) {
        self.menuView.progressViewCornerRadius = progressViewCornerRadius;
    }
}

- (void)setMenuViewLayoutMode:(WMMenuViewLayoutMode)menuViewLayoutMode {
    _menuViewLayoutMode = menuViewLayoutMode;
    if (self.menuView.superview) {
        [self wm_resetMenuView];
    }
}

- (void)setCachePolicy:(WMPageControllerCachePolicy)cachePolicy {
    _cachePolicy = cachePolicy;
    if (cachePolicy != WMPageControllerCachePolicyDisabled) {
        self.memCache.countLimit = _cachePolicy;
    }
}

- (void)setSelectIndex:(int)selectIndex {
    _selectIndex = selectIndex;
    _markedSelectIndex = kWMUndefinedIndex;
    if (self.menuView && _hasInited) {
        [self.menuView selectItemAtIndex:selectIndex];
    } else {
        _markedSelectIndex = selectIndex;
    }
}

- (void)setProgressViewIsNaughty:(BOOL)progressViewIsNaughty {
    _progressViewIsNaughty = progressViewIsNaughty;
    if (self.menuView) {
        self.menuView.progressViewIsNaughty = progressViewIsNaughty;
    }
}

- (void)setProgressWidth:(CGFloat)progressWidth {
    _progressWidth = progressWidth;
    self.progressViewWidths = ({
        NSMutableArray *tmp = [NSMutableArray array];
        for (int i = 0; i < self.childControllersCount; i++) {
            [tmp addObject:@(progressWidth)];
        }
        tmp.copy;
    });
}

- (void)setProgressViewWidths:(NSArray *)progressViewWidths {
    _progressViewWidths = progressViewWidths;
    if (self.menuView) {
        self.menuView.progressWidths = progressViewWidths;
    }
}

- (void)setMenuViewContentMargin:(CGFloat)menuViewContentMargin {
    _menuViewContentMargin = menuViewContentMargin;
    if (self.menuView) {
        self.menuView.contentMargin = menuViewContentMargin;
    }
}

- (void)setViewFrame:(CGRect)viewFrame {
    if (CGRectEqualToRect(viewFrame, _viewFrame)) return;
    
    _viewFrame = viewFrame;
    if (self.menuView) {
        _hasInited = NO;
        [self viewDidLayoutSubviews];
    }
}

- (void)reloadData {
    [self wm_clearDatas];
    
    if (!self.childControllersCount) return;
    
    [self wm_resetScrollView];
    [self.memCache removeAllObjects];
    [self wm_resetMenuView];
    [self viewDidLayoutSubviews];
}

- (void)updateTitle:(NSString *)title atIndex:(NSInteger)index {
    [self.menuView updateTitle:title atIndex:index andWidth:NO];
}

- (void)updateAttributeTitle:(NSAttributedString * _Nonnull)title atIndex:(NSInteger)index {
    [self.menuView updateAttributeTitle:title atIndex:index andWidth:NO];
}

- (void)updateTitle:(NSString *)title andWidth:(CGFloat)width atIndex:(NSInteger)index {
    if (self.itemsWidths && index < self.itemsWidths.count) {
        NSMutableArray *mutableWidths = [NSMutableArray arrayWithArray:self.itemsWidths];
        mutableWidths[index] = @(width);
        self.itemsWidths = [mutableWidths copy];
    } else {
        NSMutableArray *mutableWidths = [NSMutableArray array];
        for (int i = 0; i < self.childControllersCount; i++) {
            CGFloat itemWidth = (i == index) ? width : self.menuItemWidth;
            [mutableWidths addObject:@(itemWidth)];
        }
        self.itemsWidths = [mutableWidths copy];
    }
    [self.menuView updateTitle:title atIndex:index andWidth:YES];
}

- (void)setShowOnNavigationBar:(BOOL)showOnNavigationBar {
    if (_showOnNavigationBar == showOnNavigationBar) {
        return;
    }
    
    _showOnNavigationBar = showOnNavigationBar;
    if (self.menuView) {
        [self.menuView removeFromSuperview];
        [self wm_addMenuView];
        [self forceLayoutSubviews];
        [self.menuView slideMenuAtProgress:self.selectIndex];
    }
}

#pragma mark - Notification
- (void)willResignActive:(NSNotification *)notification {
    for (int i = 0; i < self.childControllersCount; i++) {
        id obj = [self.memCache objectForKey:@(i)];
        if (obj) {
            [self.backgroundCache setObject:obj forKey:@(i)];
        }
    }
}

- (void)willEnterForeground:(NSNotification *)notification {
    for (NSNumber *key in self.backgroundCache.allKeys) {
        if (![self.memCache objectForKey:key]) {
            [self.memCache setObject:self.backgroundCache[key] forKey:key];
        }
    }
    [self.backgroundCache removeAllObjects];
}

#pragma mark - Delegate
- (NSDictionary *)infoWithIndex:(NSInteger)index {
    NSString *title = [self titleAtIndex:index];
    return @{@"title": title ? title : @"", @"index": @(index)};
}

- (void)willCachedController:(UIViewController *)vc atIndex:(NSInteger)index {
    if (self.childControllersCount && [self.delegate respondsToSelector:@selector(pageController:willCachedViewController:withInfo:)]) {
        NSDictionary *info = [self infoWithIndex:index];
        [self.delegate pageController:self willCachedViewController:vc withInfo:info];
    }
}

- (void)willEnterController:(UIViewController *)vc atIndex:(NSInteger)index {
    _selectIndex = (int)index;
    if (self.childControllersCount && [self.delegate respondsToSelector:@selector(pageController:willEnterViewController:withInfo:)]) {
        NSDictionary *info = [self infoWithIndex:index];
        [self.delegate pageController:self willEnterViewController:vc withInfo:info];
    }
}

// 完全进入控制器 (即停止滑动后调用)
- (void)didEnterController:(UIViewController *)vc atIndex:(NSInteger)index {
    if (!self.childControllersCount) return;
    NSDictionary *info = [self infoWithIndex:index];
    if ([self.delegate respondsToSelector:@selector(pageController:didEnterViewController:withInfo:)]) {
        [self.delegate pageController:self didEnterViewController:vc withInfo:info];
    }
    
    // 当控制器创建时，调用延迟加载的代理方法
    if (_initializedIndex == index && [self.delegate respondsToSelector:@selector(pageController:lazyLoadViewController:withInfo:)]) {
        [self.delegate pageController:self lazyLoadViewController:vc withInfo:info];
        _initializedIndex = kWMUndefinedIndex;
    }

    // 根据 preloadPolicy 预加载控制器
    if (self.preloadPolicy == WMPageControllerPreloadPolicyNever) return;
    int start = 0;
    int end = (int)self.childControllersCount - 1;
    if (index > self.preloadPolicy) {
        start = (int)index - self.preloadPolicy;
    }
    if (self.childControllersCount - 1 > self.preloadPolicy + index) {
        end = (int)index + self.preloadPolicy;
    }
    for (int i = start; i <= end; i++) {
        // 如果已存在，不需要预加载
        if (![self.memCache objectForKey:@(i)] && !self.displayVC[@(i)]) {
            [self wm_addViewControllerAtIndex:i];
            [self wm_postAddToSuperViewNotificationWithIndex:i];
        }
    }
    _selectIndex = (int)index;
}

#pragma mark - Data source
- (NSInteger)childControllersCount {
    if (_controllerConut == kWMControllerCountUndefined) {
        if ([self.dataSource respondsToSelector:@selector(numbersOfChildControllersInPageController:)]) {
            _controllerConut = [self.dataSource numbersOfChildControllersInPageController:self];
        } else {
            _controllerConut = self.viewControllerClasses.count;
        }
    }
    return _controllerConut;
}

- (UIViewController * _Nonnull)initializeViewControllerAtIndex:(NSInteger)index {
    if ([self.dataSource respondsToSelector:@selector(pageController:viewControllerAtIndex:)]) {
        return [self.dataSource pageController:self viewControllerAtIndex:index];
    }
    MIScene *viewScene = [MIScene sceneWithView:[NSString stringWithFormat:@"%@showView",self.viewControllerClasses[index]] controller:[NSString stringWithFormat:@"%@showViewController",self.viewControllerClasses[index]] store:[NSString stringWithFormat:@"%@showStore",self.viewControllerClasses[index]]];
    UIViewController *viewController = [[MIMediator sharedMediator] viewControllerWithScene:viewScene context:nil];
    return viewController;
}

- (NSString * _Nonnull)titleAtIndex:(NSInteger)index {
    NSString *title = nil;
    if ([self.dataSource respondsToSelector:@selector(pageController:titleAtIndex:)]) {
        title = [self.dataSource pageController:self titleAtIndex:index];
    } else {
        title = self.titles[index];
    }
    return (title ? title : @"");
}

#pragma mark - Private Methods

- (void)wm_resetScrollView {
    if (self.scrollView) {
        [self.scrollView removeFromSuperview];
    }
    [self wm_addScrollView];
    [self wm_addViewControllerAtIndex:self.selectIndex];
    self.currentViewController = self.displayVC[@(self.selectIndex)];
}

- (void)wm_clearDatas {
    _controllerConut = kWMControllerCountUndefined;
    _hasInited = NO;
    NSUInteger maxIndex = (self.childControllersCount - 1 > 0) ? (self.childControllersCount - 1) : 0;
    _selectIndex = self.selectIndex < self.childControllersCount ? self.selectIndex : (int)maxIndex;
    if (self.progressWidth > 0) { self.progressWidth = self.progressWidth; }
    
    NSArray *displayingViewControllers = self.displayVC.allValues;
    for (UIViewController *vc in displayingViewControllers) {
        [vc.view removeFromSuperview];
        [vc willMoveToParentViewController:nil];
        [vc removeFromParentViewController];
    }
    self.memoryWarningCount = 0;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(wm_growCachePolicyAfterMemoryWarning) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(wm_growCachePolicyToHigh) object:nil];
    self.currentViewController = nil;
    [self.posRecords removeAllObjects];
    [self.displayVC removeAllObjects];
}

// 当子控制器init完成时发送通知
- (void)wm_postAddToSuperViewNotificationWithIndex:(int)index {
    if (!self.postNotification) return;
    NSDictionary *info = @{
                           @"index":@(index),
                           @"title":[self titleAtIndex:index]
                           };
    [[NSNotificationCenter defaultCenter] postNotificationName:WMControllerDidAddToSuperViewNotification
                                                        object:info];
}

// 当子控制器完全展示在user面前时发送通知
- (void)wm_postFullyDisplayedNotificationWithCurrentIndex:(int)index {
    if (!self.postNotification) return;
    NSDictionary *info = @{
                           @"index":@(index),
                           @"title":[self titleAtIndex:index]
                           };
    [[NSNotificationCenter defaultCenter] postNotificationName:WMControllerDidFullyDisplayedNotification
                                                        object:info];
}

// 初始化一些参数，在init中调用
- (void)wm_setup {
    
    _titleSizeSelected  = 18.0f;
    _titleSizeNormal    = 15.0f;
    _titleColorSelected = [UIColor colorWithRed:168.0/255.0 green:20.0/255.0 blue:4/255.0 alpha:1];
    _titleColorNormal   = [UIColor colorWithRed:0 green:0 blue:0 alpha:1];
    
    _menuBGColor   = [UIColor clearColor];
    _menuHeight    = 30.0f;
    _menuItemWidth = 65.0f;
    
    _memCache = [[NSCache alloc] init];
    _initializedIndex = kWMUndefinedIndex;
    _markedSelectIndex = kWMUndefinedIndex;
    _controllerConut  = kWMControllerCountUndefined;
    _scrollEnable = YES;
    
    self.automaticallyCalculatesItemWidths = NO;
    self.automaticallyAdjustsScrollViewInsets = NO;
    self.preloadPolicy = WMPageControllerPreloadPolicyNever;
    self.cachePolicy = WMPageControllerCachePolicyNoLimit;
    
    self.delegate = self;
    self.dataSource = self;

    [self setNaviBarItems];
    self.automaticallyAdjustsScrollViewInsets = NO;
    //测试
    _allTags = @[
                 @"不限", @"上海", @"北京", @"广州", @"深圳"
                 ];
    NSArray *arr = @[@"不限",@"银行",@"证券",@"保险",@"基金",@"投资/财富管理",@"信托",@"期货",@"互联网金融",@"互联网高新",@"其它"];
    NSArray *arr1 = @[@"不限",@"近三天",@"近一周",@"近一月"];
    _cellInfos = [NSMutableArray new];
    [_cellInfos addObjectsFromArray:@[_allTags,arr,arr1]];

    //测试
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
}

// 包括宽高，子控制器视图 frame
- (void)wm_calculateSize {
    CGFloat navigationHeight = CGRectGetMaxY(self.navigationController.navigationBar.frame);
    UIView *tabBar = [self wm_bottomView];
    CGFloat height = (tabBar && !tabBar.hidden) ? CGRectGetHeight(tabBar.frame) : 0;
    CGFloat tarBarHeight = (self.hidesBottomBarWhenPushed == YES) ? 0 : height;
    // 计算相对 window 的绝对 frame (self.view.window 可能为 nil)
    UIWindow *mainWindow = [[UIApplication sharedApplication].delegate window];
    CGRect absoluteRect = [self.view convertRect:self.view.bounds toView:mainWindow];
    navigationHeight -= absoluteRect.origin.y;
    tarBarHeight -= mainWindow.frame.size.height - CGRectGetMaxY(absoluteRect);
    
    _viewX = self.viewFrame.origin.x;
    _viewY = self.viewFrame.origin.y;
    if (CGRectEqualToRect(self.viewFrame, CGRectZero)) {
        _viewWidth = self.view.frame.size.width;
        _viewHeight = self.view.frame.size.height - self.menuHeight - self.menuViewBottomSpace - navigationHeight - tarBarHeight;
        _viewY += navigationHeight;
    } else {
        _viewWidth = self.viewFrame.size.width;
        _viewHeight = self.viewFrame.size.height - self.menuHeight - self.menuViewBottomSpace;
    }
    if (self.showOnNavigationBar && self.navigationController.navigationBar) {
        _viewHeight += self.menuHeight;
    }    // 重新计算各个控制器视图的宽高
    _childViewFrames = [NSMutableArray array];
    for (int i = 0; i < self.childControllersCount; i++) {
        CGRect frame = CGRectMake(i*_viewWidth, 0, _viewWidth, _viewHeight);
        [_childViewFrames addObject:[NSValue valueWithCGRect:frame]];
    }
}

- (void)wm_addScrollView {
    WMScrollView *scrollView = [[WMScrollView alloc] init];
    scrollView.scrollsToTop = NO;
    scrollView.pagingEnabled = YES;
    scrollView.backgroundColor = [UIColor whiteColor];
    scrollView.delegate = self;
    scrollView.showsVerticalScrollIndicator = NO;
    scrollView.showsHorizontalScrollIndicator = NO;
    scrollView.bounces = self.bounces;
    scrollView.otherGestureRecognizerSimultaneously = self.otherGestureRecognizerSimultaneously;
    scrollView.scrollEnabled = self.scrollEnable;
    [self.view addSubview:scrollView];
    self.scrollView = scrollView;
    
    if (!self.navigationController) return;
    for (UIGestureRecognizer *gestureRecognizer in scrollView.gestureRecognizers) {
        [gestureRecognizer requireGestureRecognizerToFail:self.navigationController.interactivePopGestureRecognizer];
    }
}

- (void)wm_addMenuView {
    CGFloat menuY = _viewY;
    if (self.showOnNavigationBar && self.navigationController.navigationBar) {
        CGFloat navHeight = self.navigationController.navigationBar.frame.size.height;
        CGFloat menuHeight = self.menuHeight > navHeight ? navHeight : self.menuHeight;
        menuY = (navHeight - menuHeight) / 2;
    }
    
    CGRect frame = CGRectMake(_viewX, menuY, _viewWidth, self.menuHeight);
    WMMenuView *menuView = [[WMMenuView alloc] initWithFrame:frame];
    menuView.backgroundColor = self.menuBGColor;
    menuView.delegate = self;
    menuView.dataSource = self;
    menuView.style = self.menuViewStyle;
    menuView.layoutMode = self.menuViewLayoutMode;
    menuView.progressHeight = self.progressHeight;
    menuView.contentMargin = self.menuViewContentMargin;
    menuView.progressViewBottomSpace = self.progressViewBottomSpace;
    menuView.progressWidths = self.progressViewWidths;
    menuView.progressViewIsNaughty = self.progressViewIsNaughty;
    menuView.progressViewCornerRadius = self.progressViewCornerRadius;
    if (self.titleFontName) {
        menuView.fontName = self.titleFontName;
    }
    if (self.progressColor) {
        menuView.lineColor = self.progressColor;
    }
    if (self.showOnNavigationBar && self.navigationController.navigationBar) {
        self.navigationItem.titleView = menuView;
    } else {
        [self.view addSubview:menuView];
    }
    self.menuView = menuView;
}

- (void)wm_layoutChildViewControllers {
    int currentPage = (int)(self.scrollView.contentOffset.x / _viewWidth);
    int start = currentPage == 0 ? currentPage : (currentPage - 1);
    int end = (currentPage == self.childControllersCount - 1) ? currentPage : (currentPage + 1);
    for (int i = start; i <= end; i++) {
        CGRect frame = [self.childViewFrames[i] CGRectValue];
        UIViewController *vc = [self.displayVC objectForKey:@(i)];
        if ([self wm_isInScreen:frame]) {
            if (vc == nil) {
                [self wm_initializedControllerWithIndexIfNeeded:i];
            }
        } else {
            if (vc) {
                // vc不在视野中且存在，移除他
                [self wm_removeViewController:vc atIndex:i];
            }
        }
    }
}

// 创建或从缓存中获取控制器并添加到视图上
- (void)wm_initializedControllerWithIndexIfNeeded:(NSInteger)index {
    // 先从 cache 中取
    UIViewController *vc = [self.memCache objectForKey:@(index)];
    if (vc) {
        // cache 中存在，添加到 scrollView 上，并放入display
        [self wm_addCachedViewController:vc atIndex:index];
    } else {
        // cache 中也不存在，创建并添加到display
        [self wm_addViewControllerAtIndex:(int)index];
    }
    [self wm_postAddToSuperViewNotificationWithIndex:(int)index];
}

- (void)wm_removeSuperfluousViewControllersIfNeeded {
    [self.displayVC enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, UIViewController * _Nonnull vc, BOOL * _Nonnull stop) {
        NSInteger index = key.integerValue;
        CGRect frame = [self.childViewFrames[index] CGRectValue];
        if (![self wm_isInScreen:frame]) {
            [self wm_removeViewController:vc atIndex:index];
        }
    }];
}

- (void)wm_addCachedViewController:(UIViewController *)viewController atIndex:(NSInteger)index {
    [self addChildViewController:viewController];
    viewController.view.frame = [self.childViewFrames[index] CGRectValue];
    [viewController didMoveToParentViewController:self];
    [self.scrollView addSubview:viewController.view];
    [self willEnterController:viewController atIndex:index];
    [self.displayVC setObject:viewController forKey:@(index)];
}

// 创建并添加子控制器
- (void)wm_addViewControllerAtIndex:(int)index {
    _initializedIndex = index;
    UIViewController *viewController = [self initializeViewControllerAtIndex:index];
    if (self.values.count == self.childControllersCount && self.keys.count == self.childControllersCount) {
        [viewController setValue:self.values[index] forKey:self.keys[index]];
    }
    [self addChildViewController:viewController];
    CGRect frame = self.childViewFrames.count ? [self.childViewFrames[index] CGRectValue] : self.view.frame;
    viewController.view.frame = frame;
    [viewController didMoveToParentViewController:self];
    [self.scrollView addSubview:viewController.view];
    [self willEnterController:viewController atIndex:index];
    [self.displayVC setObject:viewController forKey:@(index)];
    
    [self wm_backToPositionIfNeeded:viewController atIndex:index];
}

// 移除控制器，且从display中移除
- (void)wm_removeViewController:(UIViewController *)viewController atIndex:(NSInteger)index {
    [self wm_rememberPositionIfNeeded:viewController atIndex:index];
    [viewController.view removeFromSuperview];
    [viewController willMoveToParentViewController:nil];
    [viewController removeFromParentViewController];
    [self.displayVC removeObjectForKey:@(index)];
    
    // 放入缓存
    if (self.cachePolicy == WMPageControllerCachePolicyDisabled) {
        return;
    }
    
    if (![self.memCache objectForKey:@(index)]) {
        [self willCachedController:viewController atIndex:index];
        [self.memCache setObject:viewController forKey:@(index)];
    }
}

- (void)wm_backToPositionIfNeeded:(UIViewController *)controller atIndex:(NSInteger)index {
#pragma clang diagnostic push
#pragma clang diagnostic ignored"-Wdeprecated-declarations"
    if (!self.rememberLocation) return;
#pragma clang diagnostic pop
    if ([self.memCache objectForKey:@(index)]) return;
    UIScrollView *scrollView = [self wm_isKindOfScrollViewController:controller];
    if (scrollView) {
        NSValue *pointValue = self.posRecords[@(index)];
        if (pointValue) {
            CGPoint pos = [pointValue CGPointValue];
            [scrollView setContentOffset:pos];
        }
    }
}

- (void)wm_rememberPositionIfNeeded:(UIViewController *)controller atIndex:(NSInteger)index {
#pragma clang diagnostic push
#pragma clang diagnostic ignored"-Wdeprecated-declarations"
    if (!self.rememberLocation) return;
#pragma clang diagnostic pop
    UIScrollView *scrollView = [self wm_isKindOfScrollViewController:controller];
    if (scrollView) {
        CGPoint pos = scrollView.contentOffset;
        self.posRecords[@(index)] = [NSValue valueWithCGPoint:pos];
    }
}

- (UIScrollView *)wm_isKindOfScrollViewController:(UIViewController *)controller {
    UIScrollView *scrollView = nil;
    if ([controller.view isKindOfClass:[UIScrollView class]]) {
        // Controller的view是scrollView的子类(UITableViewController/UIViewController替换view为scrollView)
        scrollView = (UIScrollView *)controller.view;
    } else if (controller.view.subviews.count >= 1) {
        // Controller的view的subViews[0]存在且是scrollView的子类，并且frame等与view得frame(UICollectionViewController/UIViewController添加UIScrollView)
        UIView *view = controller.view.subviews[0];
        if ([view isKindOfClass:[UIScrollView class]]) {
            scrollView = (UIScrollView *)view;
        }
    }
    return scrollView;
}

- (BOOL)wm_isInScreen:(CGRect)frame {
    CGFloat x = frame.origin.x;
    CGFloat ScreenWidth = self.scrollView.frame.size.width;
    
    CGFloat contentOffsetX = self.scrollView.contentOffset.x;
    if (CGRectGetMaxX(frame) > contentOffsetX && x-contentOffsetX < ScreenWidth) {
        return YES;
    } else {
        return NO;
    }
}

- (void)wm_resetMenuView {
    if (!self.menuView) {
        [self wm_addMenuView];
    } else {
        [self.menuView reload];
        if (self.menuView.userInteractionEnabled == NO) {
            self.menuView.userInteractionEnabled = YES;
        }
        if (self.selectIndex != 0) {
            [self.menuView selectItemAtIndex:self.selectIndex];
        }
        [self.view bringSubviewToFront:self.menuView];
    }
}

- (void)wm_growCachePolicyAfterMemoryWarning {
    self.cachePolicy = WMPageControllerCachePolicyBalanced;
    [self performSelector:@selector(wm_growCachePolicyToHigh) withObject:nil afterDelay:2.0 inModes:@[NSRunLoopCommonModes]];
}

- (void)wm_growCachePolicyToHigh {
    self.cachePolicy = WMPageControllerCachePolicyHigh;
}

- (UIView *)wm_bottomView {
    return self.tabBarController.tabBar ? self.tabBarController.tabBar : self.navigationController.toolbar;
}

#pragma mark - Adjust Frame
- (void)wm_adjustScrollViewFrame {
    // While rotate at last page, set scroll frame will call `-scrollViewDidScroll:` delegate
    // It's not my expectation, so I use `_shouldNotScroll` to lock it.
    // Wait for a better solution.
    _shouldNotScroll = YES;
    CGRect scrollFrame = CGRectMake(_viewX, _viewY + self.menuHeight + self.menuViewBottomSpace, _viewWidth, _viewHeight);
    CGFloat oldContentOffsetX = self.scrollView.contentOffset.x;
    CGFloat contentWidth = self.scrollView.contentSize.width;
    scrollFrame.origin.y -= self.showOnNavigationBar && self.navigationController.navigationBar ? self.menuHeight : 0;
    self.scrollView.frame = scrollFrame;
    self.scrollView.contentSize = CGSizeMake(self.childControllersCount * _viewWidth, 0);
    CGFloat xContentOffset = contentWidth == 0 ? self.selectIndex * _viewWidth : oldContentOffsetX / contentWidth * self.childControllersCount * _viewWidth;
    [self.scrollView setContentOffset:CGPointMake(xContentOffset, 0)];
    _shouldNotScroll = NO;
}

- (void)wm_adjustDisplayingViewControllersFrame {
    [self.displayVC enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, UIViewController * _Nonnull vc, BOOL * _Nonnull stop) {
        NSInteger index = key.integerValue;
        CGRect frame = [self.childViewFrames[index] CGRectValue];
        vc.view.frame = frame;
    }];
}

- (void)wm_adjustMenuViewFrame {
    // 根据是否在导航栏上展示调整frame
    CGFloat menuHeight = self.menuHeight;
    __block CGFloat menuX = _viewX;
    __block CGFloat menuY = _viewY;
    __block CGFloat rightWidth = 0;
    if (self.showOnNavigationBar && self.navigationController.navigationBar) {
        [self.navigationController.navigationBar.subviews enumerateObjectsUsingBlock:^(UIView* obj, NSUInteger idx, BOOL *stop) {
            if (![obj isKindOfClass:[WMMenuView class]] && ![obj isKindOfClass:NSClassFromString(@"_UINavigationBarBackground")] && obj.alpha != 0 && obj.hidden == NO) {
                CGFloat maxX = CGRectGetMaxX(obj.frame);
                if (maxX < _viewWidth / 2) {
                    CGFloat leftWidth = maxX;
                    menuX = menuX > leftWidth ? menuX : leftWidth;
                }
                CGFloat minX = CGRectGetMinX(obj.frame);
                if (minX > _viewWidth / 2) {
                    CGFloat width = (_viewWidth - minX);
                    rightWidth = rightWidth > width ? rightWidth : width;
                }
            }
        }];
        CGFloat navHeight = self.navigationController.navigationBar.frame.size.height;
        menuHeight = self.menuHeight > navHeight ? navHeight : self.menuHeight;
        menuY = (navHeight - menuHeight) / 2;
    }
    CGFloat menuWidth = _viewWidth - menuX - rightWidth;
    self.menuView.frame = CGRectMake(menuX, menuY, menuWidth, menuHeight);
    [self.menuView resetFrames];
}

- (CGFloat)wm_calculateItemWithAtIndex:(NSInteger)index {
    NSString *title = [self titleAtIndex:index];
    UIFont *titleFont = self.titleFontName ? [UIFont fontWithName:self.titleFontName size:self.titleSizeSelected] : [UIFont systemFontOfSize:self.titleSizeSelected];
    NSDictionary *attrs = @{NSFontAttributeName: titleFont};
    CGFloat itemWidth = [title boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX) options:(NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading) attributes:attrs context:nil].size.width;
    return ceil(itemWidth);
}

- (void)wm_delaySelectIndexIfNeeded {
    if (_markedSelectIndex != kWMUndefinedIndex) {
        self.selectIndex = (int)_markedSelectIndex;
    }
}

#pragma mark - Life Cycle
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    if (!self.childControllersCount) return;
    [self wm_calculateSize];
    [self wm_addScrollView];
    [self wm_addViewControllerAtIndex:self.selectIndex];
    self.currentViewController = self.displayVC[@(self.selectIndex)];
    [self wm_addMenuView];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    if (!self.childControllersCount) return;
    
    CGFloat oldSuperviewHeight = _superviewHeight;
    _superviewHeight = self.view.frame.size.height;
    BOOL oldTabBarIsHidden = _isTabBarHidden;
    _isTabBarHidden = [self wm_bottomView].hidden;
    
    BOOL shouldNotLayout = (_hasInited && _superviewHeight == oldSuperviewHeight && _isTabBarHidden == oldTabBarIsHidden);
    if (shouldNotLayout) return;
    // 计算宽高及子控制器的视图frame
    [self wm_calculateSize];
    [self wm_adjustScrollViewFrame];
    [self wm_adjustMenuViewFrame];
    [self wm_adjustDisplayingViewControllersFrame];
    [self wm_removeSuperfluousViewControllersIfNeeded];
    _hasInited = YES;
    [self.view layoutIfNeeded];
    [self wm_delaySelectIndexIfNeeded];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    if (!self.childControllersCount) return;
    
    [self wm_postFullyDisplayedNotificationWithCurrentIndex:self.selectIndex];
    [self didEnterController:self.currentViewController atIndex:self.selectIndex];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
    self.memoryWarningCount++;
    self.cachePolicy = WMPageControllerCachePolicyLowMemory;
    // 取消正在增长的 cache 操作
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(wm_growCachePolicyAfterMemoryWarning) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(wm_growCachePolicyToHigh) object:nil];
    
    [self.memCache removeAllObjects];
    [self.posRecords removeAllObjects];
    self.posRecords = nil;
    
    // 如果收到内存警告次数小于 3，一段时间后切换到模式 Balanced
    if (self.memoryWarningCount < 3) {
        [self performSelector:@selector(wm_growCachePolicyAfterMemoryWarning) withObject:nil afterDelay:3.0 inModes:@[NSRunLoopCommonModes]];
    }
}

#pragma mark - UIScrollView Delegate
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (![scrollView isKindOfClass:WMScrollView.class]) return;
    
    if (_shouldNotScroll || !_hasInited) return;
    
    [self wm_layoutChildViewControllers];
    if (_startDragging) {
        CGFloat contentOffsetX = scrollView.contentOffset.x;
        if (contentOffsetX < 0) {
            contentOffsetX = 0;
        }
        if (contentOffsetX > scrollView.contentSize.width - _viewWidth) {
            contentOffsetX = scrollView.contentSize.width - _viewWidth;
        }
        CGFloat rate = contentOffsetX / _viewWidth;
        [self.menuView slideMenuAtProgress:rate];
    }
   
    // Fix scrollView.contentOffset.y -> (-20) unexpectedly.
    if (scrollView.contentOffset.y == 0) return;
    CGPoint contentOffset = scrollView.contentOffset;
    contentOffset.y = 0.0;
    scrollView.contentOffset = contentOffset;
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (![scrollView isKindOfClass:WMScrollView.class]) return;
    
    _startDragging = YES;
    self.menuView.userInteractionEnabled = NO;
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (![scrollView isKindOfClass:WMScrollView.class]) return;
    
    self.menuView.userInteractionEnabled = YES;
    _selectIndex = (int)(scrollView.contentOffset.x / _viewWidth);
    [self wm_removeSuperfluousViewControllersIfNeeded];
    self.currentViewController = self.displayVC[@(self.selectIndex)];
    [self wm_postFullyDisplayedNotificationWithCurrentIndex:self.selectIndex];
    [self didEnterController:self.currentViewController atIndex:self.selectIndex];
    [self.menuView deselectedItemsIfNeeded];
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    if (![scrollView isKindOfClass:WMScrollView.class]) return;
    
    self.currentViewController = self.displayVC[@(self.selectIndex)];
    [self wm_removeSuperfluousViewControllersIfNeeded];
    [self wm_postFullyDisplayedNotificationWithCurrentIndex:self.selectIndex];
    [self didEnterController:self.currentViewController atIndex:self.selectIndex];
    [self.menuView deselectedItemsIfNeeded];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (![scrollView isKindOfClass:WMScrollView.class]) return;
    
    if (!decelerate) {
        self.menuView.userInteractionEnabled = YES;
        CGFloat rate = _targetX / _viewWidth;
        [self.menuView slideMenuAtProgress:rate];
        [self.menuView deselectedItemsIfNeeded];
    }
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset {
    if (![scrollView isKindOfClass:WMScrollView.class]) return;
    
    _targetX = targetContentOffset->x;
}

#pragma mark - WMMenuView Delegate
- (void)menuView:(WMMenuView *)menu didSelesctedIndex:(NSInteger)index currentIndex:(NSInteger)currentIndex {
    if (!_hasInited) return;
    _selectIndex = (int)index;
    _startDragging = NO;
    CGPoint targetP = CGPointMake(_viewWidth*index, 0);
    [self.scrollView setContentOffset:targetP animated:self.pageAnimatable];
    if (!self.pageAnimatable) {
        // 由于不触发 -scrollViewDidScroll: 手动处理控制器
        [self wm_removeSuperfluousViewControllersIfNeeded];
        UIViewController *currentViewController = self.displayVC[@(currentIndex)];
        if (currentViewController) {
            [self wm_removeViewController:currentViewController atIndex:currentIndex];
        }
        [self wm_layoutChildViewControllers];
        self.currentViewController = self.displayVC[@(self.selectIndex)];
        [self wm_postFullyDisplayedNotificationWithCurrentIndex:(int)index];
        [self didEnterController:self.currentViewController atIndex:index];
    }
}

- (CGFloat)menuView:(WMMenuView *)menu widthForItemAtIndex:(NSInteger)index {
    if (self.automaticallyCalculatesItemWidths) {
        return [self wm_calculateItemWithAtIndex:index];
    }
    
    if (self.itemsWidths.count == self.childControllersCount) {
        return [self.itemsWidths[index] floatValue];
    }
    return self.menuItemWidth;
}

- (CGFloat)menuView:(WMMenuView *)menu itemMarginAtIndex:(NSInteger)index {
    if (self.itemsMargins.count == self.childControllersCount + 1) {
        return [self.itemsMargins[index] floatValue];
    }
    return self.itemMargin;
}

- (CGFloat)menuView:(WMMenuView *)menu titleSizeForState:(WMMenuItemState)state atIndex:(NSInteger)index {
    switch (state) {
        case WMMenuItemStateSelected: {
            return self.titleSizeSelected;
            break;
        }
        case WMMenuItemStateNormal: {
            return self.titleSizeNormal;
            break;
        }
    }
}

- (UIColor *)menuView:(WMMenuView *)menu titleColorForState:(WMMenuItemState)state atIndex:(NSInteger)index {
    switch (state) {
        case WMMenuItemStateSelected: {
            return self.titleColorSelected;
            break;
        }
        case WMMenuItemStateNormal: {
            return self.titleColorNormal;
            break;
        }
    }
}

#pragma mark - WMMenuViewDataSource
- (NSInteger)numbersOfTitlesInMenuView:(WMMenuView *)menu {
    return self.childControllersCount;
}

- (NSString *)menuView:(WMMenuView *)menu titleAtIndex:(NSInteger)index {
    return [self titleAtIndex:index];
}

#pragma mark self done

- (void)setNaviBarItems
{
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]initWithImage:[UIImage imageNamed:@"filter_image"] style:UIBarButtonItemStylePlain target:self action:@selector(showFilterView)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]initWithImage:[UIImage imageNamed:@"search_image"] style:UIBarButtonItemStylePlain target:self action:@selector(searchJob)];
}

- (void)showFilterView
{
    [self showDropDownViewFromDirection:LMDropdownViewDirectionTop];
}

- (void)showDropDownViewFromDirection:(LMDropdownViewDirection)direction
{
        // Init dropdown view
    if (!self.dropdownView) {
        self.dropdownView = [LMDropdownView dropdownView];
        self.dropdownView.delegate = self;

            // Customize Dropdown style
        self.dropdownView.closedScale = 0.85;
        self.dropdownView.shouldBlurContainerView = YES;
        self.dropdownView.blurRadius = 1;
        self.dropdownView.blackMaskAlpha = 0.1;
        self.dropdownView.animationDuration = 0.5;
        self.dropdownView.animationBounceHeight = 0;
    }
    self.dropdownView.direction = direction;

        // Show/hide dropdown view
    AppDelegate *appdel = (AppDelegate*)[UIApplication sharedApplication].delegate;
    if ([self.dropdownView isOpen]) {
        [self.dropdownView hide];
    }
    appdel.tabBarControllerConfig.tabBarController.tabBar.hidden = YES;
    self.dropdownView.contentBackgroundColor = [UIColor whiteColor];
    [self.dropdownView showInView:self.navigationController.visibleViewController.view withContentView:self.backView atOrigin:CGPointMake(0, 64)];
}

- (UIView *)backView
{
    if (!_backView) {
        _backView = [[UIView alloc]init];
        _backView.frame = CGRectMake(0, 64, kScreen_Width, kScreen_Height-64);
        _backView.backgroundColor = [UIColor whiteColor];
        [_backView addSubview:self.tagTableView];
        [_backView addSubview:self.buttonBackView];
    }
    return _backView;
}

- (UITableView*)tagTableView
{
    if (!_tagTableView) {
        _tagTableView = [[UITableView alloc]initWithFrame:CGRectMake(0, 0, kScreen_Width, kScreen_Height-64-64) style:UITableViewStylePlain];
        _tagTableView.delegate = self;
        _tagTableView.dataSource = self;
        _tagTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        _tagTableView.estimatedRowHeight = 80;
        _tagTableView.rowHeight = UITableViewAutomaticDimension;

        _tagTableView.backgroundColor = [UIColor clearColor];
        [_tagTableView registerNib:[UINib nibWithNibName:@"TagsFilterTableViewCell" bundle:nil] forCellReuseIdentifier:NSStringFromClass([TagsFilterTableViewCell class])];
    }
    return _tagTableView;
}

- (UIView*)buttonBackView
{
    if (!_buttonBackView) {
        _buttonBackView = [[UIView alloc]init];
        _buttonBackView.frame = CGRectMake(0, kScreen_Height-64-64, kScreen_Width, 64);
        _buttonBackView.layer.borderWidth = 1;
        _buttonBackView.layer.borderColor = [UIColor colorWithRed:0.627 green:0.627 blue:0.627 alpha:.30].CGColor;
        _buttonBackView.backgroundColor = [UIColor clearColor];
        UIButton *cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
        cancelButton.frame = CGRectMake(20, 12, (kScreen_Width-55)/2, 40);
        [cancelButton setTitle:@"取消筛选" forState:UIControlStateNormal];
        [cancelButton addTarget:self action:@selector(cancelSelect) forControlEvents:UIControlEventTouchUpInside];
        [cancelButton setTitleColor:kFocusTextColor forState:UIControlStateNormal];
        cancelButton.layer.borderColor = kFocusTextColor.CGColor;
        cancelButton.layer.borderWidth = 1;
        cancelButton.layer.cornerRadius = 5;
        cancelButton.layer.masksToBounds = YES;

        UIButton *sureButton = [UIButton buttonWithType:UIButtonTypeCustom];
        sureButton.frame = CGRectMake(35 + (kScreen_Width-45)/2, 12, (kScreen_Width-45)/2, 40);
        [sureButton setTitle:@"确定" forState:UIControlStateNormal];
        [sureButton addTarget:self action:@selector(sureSelect) forControlEvents:UIControlEventTouchUpInside];
        [sureButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        sureButton.backgroundColor = kFocusTextColor;
        sureButton.layer.cornerRadius = 5;
        sureButton.layer.masksToBounds = YES;
        [_buttonBackView addSubview:cancelButton];
        [_buttonBackView addSubview:sureButton];

    }
    return _buttonBackView;
}

- (void)cancelSelect
{
    [self.dropdownView hide];
}

- (void)sureSelect
{
    [self.dropdownView hide];
    [self getAllTags];

}

- (void)getAllTags
{
    NSMutableArray *tagArr = @[].mutableCopy;
    for (int i = 0; i<_cellInfos.count; i++) {
        TagsFilterTableViewCell *cell = [self.tagTableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0]];
        NSArray *tags = [cell.tagListView allSelectedTags];
        if (tags.count>0) {
            [tagArr addObject:tags.firstObject];
        }
    }
    for (NSString *a in tagArr) {

        DeBugLog(@"%@",a);
    }
}
#pragma mark - Table view data source

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _cellInfos.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    TagsFilterTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:NSStringFromClass([TagsFilterTableViewCell class])
                                                                    forIndexPath:indexPath];
    [cell setTags:_cellInfos[(NSUInteger) indexPath.row]];
    switch (indexPath.row) {
        case 0:
            cell.tagTitle.text = @"城市";
            break;
        case 1:
            cell.tagTitle.text = @"行业";
            break;
        case 2:
            cell.tagTitle.text = @"发布时间";
            break;

        default:
            break;
    }

    return cell;
}

#pragma mark LMDDropView

- (void)dropdownViewWillShow:(LMDropdownView *)dropdownView
{
    NSLog(@"Dropdown view will show");
}

- (void)dropdownViewDidShow:(LMDropdownView *)dropdownView
{
    NSLog(@"Dropdown view did show");
}

- (void)dropdownViewWillHide:(LMDropdownView *)dropdownView
{
    NSLog(@"Dropdown view will hide");

}

- (void)dropdownViewDidHide:(LMDropdownView *)dropdownView
{
    NSLog(@"Dropdown view did hide");
    AppDelegate *appdel = (AppDelegate*)[UIApplication sharedApplication].delegate;
    appdel.tabBarControllerConfig.tabBarController.tabBar.hidden = NO;
}

#pragma mark self search 
- (void)searchJob
{
        // 1. 创建热门搜索
    NSArray *hotSeaches = @[@"HR大培训",@"理财师专场",@"金茂大厦"];
        // 2. 创建控制器
    PYSearchViewController *searchViewController = [PYSearchViewController searchViewControllerWithHotSearches:hotSeaches searchBarPlaceholder:@"搜索资讯、活动、职位" didSearchBlock:^(PYSearchViewController *searchViewController, UISearchBar *searchBar, NSString *searchText) {
            // 如：跳转到指定控制器
            //        [searchViewController.navigationController pushViewController:[[PYTempViewController alloc] init] animated:YES];
    }];
        // 3. 设置风格
    searchViewController.hotSearchStyle = PYHotSearchStyleARCBorderTag; // 热门搜索风格根据选择
    searchViewController.searchHistoryStyle = PYHotSearchStyleDefault; // 搜索历史风格为default
    searchViewController.hotSearchStyle = PYHotSearchStyleDefault; // 热门搜索风格为默认
    searchViewController.searchHistoryStyle = PYSearchHistoryStyleBorderTag; // 搜索历史风格根据选择
                                                                             // 4. 设置代理
    searchViewController.delegate = self;
        // 5. 跳转到搜索控制器
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:searchViewController];
    [self presentViewController:nav animated:NO completion:nil];
}

#pragma mark - PYSearchViewControllerDelegate
- (void)searchViewController:(PYSearchViewController *)searchViewController searchTextDidChange:(UISearchBar *)seachBar searchText:(NSString *)searchText
{
    if (searchText.length) { // 与搜索条件再搜索
                             // 根据条件发送查询（这里模拟搜索）
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ // 搜索完毕
                                                                                                                       // 显示建议搜索结果
            NSMutableArray *searchSuggestionsM = [NSMutableArray array];
            for (int i = 0; i < arc4random_uniform(5) + 10; i++) {
                NSString *searchSuggestion = [NSString stringWithFormat:@"搜索建议 %d", i];
                [searchSuggestionsM addObject:searchSuggestion];
            }
                // 返回
            searchViewController.searchSuggestions = searchSuggestionsM;
        });
    }
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}

@end
