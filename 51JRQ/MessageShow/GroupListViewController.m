/************************************************************
  *  * Hyphenate CONFIDENTIAL 
  * __________________ 
  * Copyright (C) 2016 Hyphenate Inc. All rights reserved. 
  *  
  * NOTICE: All information contained herein is, and remains 
  * the property of Hyphenate Inc.
  * Dissemination of this information or reproduction of this material 
  * is strictly forbidden unless prior written permission is obtained
  * from Hyphenate Inc.
  */

#import "GroupListViewController.h"
#import "BaseTableViewCell.h"
#import "SearchResultTableViewController.h"
#import "UINavigationController+UIStatusBar.h"

//#import "ChatViewController.h"
//#import "CreateGroupViewController.h"
//#import "PublicGroupListViewController.h"
//#import "RealtimeSearchUtil.h"
//#import "RedPacketChatViewController.h"
//
//#import "UIViewController+SearchController.h"
@interface GroupListViewController ()<EMGroupManagerDelegate,
UISearchBarDelegate,UISearchControllerDelegate>

@property (strong, nonatomic) NSMutableArray *dataSource;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, assign) UIStatusBarStyle statusBarStyle;

@end

@implementation GroupListViewController

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        // Custom initialization
        _dataSource = [NSMutableArray array];
        self.page = 1;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.title = NSLocalizedString(@"群聊", @"Group");
    self.showRefreshHeader = YES;
    
    [self setupSearchController];
    [self setSearchBar];

    // Registered as SDK delegate
    [[EMClient sharedClient].groupManager removeDelegate:self];
    [[EMClient sharedClient].groupManager addDelegate:self delegateQueue:nil];
    [self reloadDataSource];
}

- (void)setSearchBar
{
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:[SearchResultTableViewController new]];
    self.searchController.view.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.95];
    self.searchController.delegate = self;

    UISearchBar *bar = self.searchController.searchBar;
    bar.barStyle = UIBarStyleDefault;
    bar.translucent = YES;
    bar.barTintColor = Global_mainBackgroundColor;
    bar.layer.borderColor = [UIColor clearColor].CGColor;
    bar.tintColor = Global_tintColor;
    UIImageView *view = [[[bar.subviews objectAtIndex:0] subviews] firstObject];
    view.layer.borderColor = Global_mainBackgroundColor.CGColor;
    view.layer.borderWidth = 1;

//    bar.tintColor = [UIColor whiteColor];
    bar.placeholder = @"搜索";
    bar.delegate = self;
    CGRect rect = bar.frame;
    rect.size.height = 44;
    bar.frame = rect;
    self.tableView.tableHeaderView = bar;
}


#pragma mark - UISearchBarDelegate Method

/**
 *  开始编辑
 */

- (UIStatusBarStyle)preferredStatusBarStyle;
{
    return self.statusBarStyle == 0 ? UIStatusBarStyleLightContent : UIStatusBarStyleDefault;
}
- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar
{
    self.statusBarStyle = UIStatusBarStyleLightContent;
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)didDismissSearchController:(UISearchController *)searchController
{
    self.statusBarStyle = UIStatusBarStyleDefault;
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)dealloc
{
    [[EMClient sharedClient].groupManager removeDelegate:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    // Return the number of sections.
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    // Return the number of rows in the section.
    if (section == 0) {
        return 2;
    }
    return [self.dataSource count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"GroupCell";
    BaseTableViewCell *cell = (BaseTableViewCell *)[tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    
    // Configure the cell...
    if (cell == nil) {
        cell = [[BaseTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
    }
    
    if (indexPath.section == 0) {
        switch (indexPath.row) {
            case 0:
                cell.textLabel.text = NSLocalizedString(@"新建群聊",@"Create a group");
                cell.imageView.image = [UIImage imageNamed:@"group_creategroup"];
                break;
            case 1:
                cell.textLabel.text = NSLocalizedString(@"加入公共群",@"Join public group");
                cell.imageView.image = [UIImage imageNamed:@"group_joinpublicgroup"];
                break;
            default:
                break;
        }
    } else {
        EMGroup *group = [self.dataSource objectAtIndex:indexPath.row];
        NSString *imageName = @"group_header";
//        NSString *imageName = group.isPublic ? @"groupPublicHeader" : @"groupPrivateHeader";
        cell.imageView.image = [UIImage imageNamed:imageName];
        if (group.subject && group.subject.length > 0) {
            cell.textLabel.text = group.subject;
        }
        else {
            cell.textLabel.text = group.groupId;
        }
    }
    if ([cell respondsToSelector:@selector(setSeparatorInset:)]) {
        [cell setSeparatorInset:UIEdgeInsetsZero];
    }
    if ([cell respondsToSelector:@selector(setLayoutMargins:)]) {
        [cell setLayoutMargins:UIEdgeInsetsZero];
    }
    return cell;
}

#pragma mark - Table view delegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 50;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return UITableViewCellEditingStyleDelete;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (indexPath.section == 0) {
        switch (indexPath.row) {
            case 0:
                [self createGroup];
                break;
            case 1:
                [self showPublicGroupList];
                break;
            default:
                break;
        }
    } else {
        EMGroup *group = [self.dataSource objectAtIndex:indexPath.row];
        
//        UIViewController *chatController = nil;
//#ifdef REDPACKET_AVALABLE
//        chatController = [[RedPacketChatViewController alloc] initWithConversationChatter:group.groupId conversationType:EMConversationTypeGroupChat];
//#else
//        chatController = [[ChatViewController alloc] initWithConversationChatter:group.groupId conversationType:EMConversationTypeGroupChat];
//#endif
//        chatController.title = group.subject;
//        [self.navigationController pushViewController:chatController animated:YES];
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    if (section == 0)
    {
        return 0;
    }
    else{
        return 0;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    return 5;
}

//- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
//{
//    if (section == 0)
//    {
//        return nil;
//    }
//    
//    UIView *contentView = [[UIView alloc] init];
//    [contentView setBackgroundColor:[UIColor colorWithRed:0.88 green:0.88 blue:0.88 alpha:1.0]];
//    return contentView;
//}

#pragma mark - EMGroupManagerDelegate

- (void)didUpdateGroupList:(NSArray *)groupList
{
    [self.dataSource removeAllObjects];
    [self.dataSource addObjectsFromArray:groupList];
    [self.tableView reloadData];
}
                                                       
#pragma mark - EMSearchControllerDelegate
                                                       
- (void)willSearchBegin
{
    [self tableViewDidFinishTriggerHeader:YES reload:NO];
}
                                                       
- (void)cancelButtonClicked
{
//    [[RealtimeSearchUtil currentUtil] realtimeSearchStop];
}
                                               
- (void)searchTextChangeWithString:(NSString *)aString
{
//    __weak typeof(self) weakSelf = self;
//    [[RealtimeSearchUtil currentUtil] realtimeSearchWithSource:self.dataSource searchText:aString collationStringSelector:@selector(subject) resultBlock:^(NSArray *results) {
//        if (results) {
//            dispatch_async(dispatch_get_main_queue(), ^{
//                [weakSelf.resultController.displaySource removeAllObjects];
//                [weakSelf.resultController.displaySource addObjectsFromArray:results];
//                [weakSelf.resultController.tableView reloadData];
//            });
//        }
//    }];
}

#pragma mark - private

- (void)setupSearchController
{
//    [self enableSearchController];
//    
//    __weak GroupListViewController *weakSelf = self;
//    [self.resultController setCellForRowAtIndexPathCompletion:^UITableViewCell *(UITableView *tableView, NSIndexPath *indexPath) {
//        static NSString *CellIdentifier = @"ContactListCell";
//        BaseTableViewCell *cell = (BaseTableViewCell *)[tableView dequeueReusableCellWithIdentifier:CellIdentifier];
//
//        // Configure the cell...
//        if (cell == nil) {
//            cell = [[BaseTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
//        }
//
//        EMGroup *group = [weakSelf.resultController.displaySource objectAtIndex:indexPath.row];
//        NSString *imageName = group.isPublic ? @"groupPublicHeader" : @"groupPrivateHeader";
//        cell.imageView.image = [UIImage imageNamed:imageName];
//        cell.textLabel.text = group.subject;
//
//        return cell;
//    }];
//
//    [self.resultController setHeightForRowAtIndexPathCompletion:^CGFloat(UITableView *tableView, NSIndexPath *indexPath) {
//        return 50;
//    }];
//
//    [self.resultController setDidSelectRowAtIndexPathCompletion:^(UITableView *tableView, NSIndexPath *indexPath) {
//        [tableView deselectRowAtIndexPath:indexPath animated:YES];
//
//        EMGroup *group = [weakSelf.resultController.displaySource objectAtIndex:indexPath.row];
//        UIViewController *chatVC = nil;
//#ifdef REDPACKET_AVALABLE
//        chatVC = [[RedPacketChatViewController alloc] initWithConversationChatter:group.groupId conversationType:EMConversationTypeGroupChat];
//#else
//        chatVC = [[ChatViewController alloc] initWithConversationChatter:group.groupId conversationType:EMConversationTypeGroupChat];
//#endif
//        chatVC.title = group.subject;
//        [weakSelf.navigationController pushViewController:chatVC animated:YES];
//                                               
//        [weakSelf cancelSearch];
//    }];
//    
//    UISearchBar *searchBar = self.searchController.searchBar;
//    self.tableView.tableHeaderView = searchBar;
}
                                                       
#pragma mark - data

- (void)tableViewDidTriggerHeaderRefresh
{
    self.page = 1;
    [self fetchGroupsWithPage:self.page isHeader:YES];
}

- (void)tableViewDidTriggerFooterRefresh
{
    self.page += 1;
    [self fetchGroupsWithPage:self.page isHeader:NO];
}

- (void)fetchGroupsWithPage:(NSInteger)aPage
                   isHeader:(BOOL)aIsHeader
{
    [self hideHud];
    [self showHudInView:self.view hint:NSLocalizedString(@"加载中...", @"Load data...")];
    
    __weak typeof(self) weakSelf = self;
    [[EMClient sharedClient].groupManager getJoinedGroupsFromServerWithCompletion:^(NSArray *aList, EMError *aError) {
        [weakSelf tableViewDidFinishTriggerHeader:aIsHeader reload:NO];

        if (weakSelf)
        {
            GroupListViewController *strongSelf = weakSelf;
            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf hideHud];

                if (!aError)
                {
                    if (aIsHeader) {
                        NSMutableArray *oldChatrooms = [weakSelf.dataSource mutableCopy];
                        [weakSelf.dataSource removeAllObjects];
                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                            [oldChatrooms removeAllObjects];
                        });
                    }

                    [strongSelf.dataSource addObjectsFromArray:aList];
                    [strongSelf.tableView reloadData];
//                    if (aList.count == 50) {
//                        strongSelf.showRefreshFooter = YES;
//                    } else {
//                        strongSelf.showRefreshFooter = NO;
//                    }
                }
            });
        }
    }];
//    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//        EMError *error = nil;
//        NSArray *groupList = [[EMClient sharedClient].groupManager getJoinedGroupsFromServerWithPage:aPage pageSize:50 error:&error];
//
//        [weakSelf tableViewDidFinishTriggerHeader:aIsHeader reload:NO];
//        
//        if (weakSelf)
//        {
//            GroupListViewController *strongSelf = weakSelf;
//            dispatch_async(dispatch_get_main_queue(), ^{
//                [strongSelf hideHud];
//                
//                if (!error)
//                {
//                    if (aIsHeader) {
//                        NSMutableArray *oldChatrooms = [weakSelf.dataSource mutableCopy];
//                        [weakSelf.dataSource removeAllObjects];
//                        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//                            [oldChatrooms removeAllObjects];
//                        });
//                    }
//                    
//                    [strongSelf.dataSource addObjectsFromArray:groupList];
//                    [strongSelf.tableView reloadData];
//                    if (groupList.count == 50) {
//                        strongSelf.showRefreshFooter = YES;
//                    } else {
//                        strongSelf.showRefreshFooter = NO;
//                    }
//                }
//            });
//        }
//    });
}

- (void)reloadDataSource
{
    [self.dataSource removeAllObjects];
    
    NSArray *rooms = [[EMClient sharedClient].groupManager getJoinedGroups];
    [self.dataSource addObjectsFromArray:rooms];
    
    [self.tableView reloadData];
}

#pragma mark - action

- (void)showPublicGroupList
{
//    PublicGroupListViewController *publicController = [[PublicGroupListViewController alloc] initWithStyle:UITableViewStylePlain];
//    [self.navigationController pushViewController:publicController animated:YES];
}

- (void)createGroup
{
//    CreateGroupViewController *createChatroom = [[CreateGroupViewController alloc] init];
//    [self.navigationController pushViewController:createChatroom animated:YES];
}


@end
