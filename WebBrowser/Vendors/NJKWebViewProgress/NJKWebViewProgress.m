//
//  NJKWebViewProgress.m
//
//  Created by Satoshi Aasano on 4/20/13.
//  Copyright (c) 2013 Satoshi Asano. All rights reserved.
//

#import "NJKWebViewProgress.h"
#import "BrowserWebView.h"

NSString *completeRPCURLPath = @"/njkwebviewprogressproxy/complete";

const float NJKInitialProgressValue = 0.1f;
const float NJKInteractiveProgressValue = 0.5f;
const float NJKFinalProgressValue = 0.9f;

@implementation NJKWebViewProgress
{
    NSUInteger _loadingCount;
    NSUInteger _maxLoadCount;
    NSURL *_currentURL;
    BOOL _interactive;
}

- (id)init
{
    self = [super init];
    if (self) {
        _maxLoadCount = _loadingCount = 0;
        _interactive = NO;
    }
    return self;
}

- (void)startProgress
{
    if (_progress < NJKInitialProgressValue) {
        [self setProgress:NJKInitialProgressValue];
    }
}

- (void)incrementProgress
{
    float progress = self.progress;
    float maxProgress = _interactive ? NJKFinalProgressValue : NJKInteractiveProgressValue;
    float remainPercent = (float)_loadingCount / (float)_maxLoadCount;
    float increment = (maxProgress - progress) * remainPercent;
    progress += increment;
    progress = fmin(progress, maxProgress);
    [self setProgress:progress];
}

- (void)completeProgress
{
    [self setProgress:1.0];
}

- (void)setProgress:(float)progress
{
    // progress should be incremental only
    if (progress > _progress || progress == 0) {
        _progress = progress;
        if ([_progressDelegate respondsToSelector:@selector(webViewProgress:updateProgress:)]) {
            [_progressDelegate webViewProgress:self updateProgress:progress];
        }
        if (_progressBlock) {
            _progressBlock(progress);
        }
    }
}

- (void)reset
{
    _maxLoadCount = _loadingCount = 0;
    _interactive = NO;
    [self setProgress:0.0];
}

- (BOOL)isFragmentJumpWithWKWebView:(WKWebView *)webView request:(NSURLRequest *)request{
    BOOL isFragmentJump = NO;
    if (request.URL.fragment) {
        NSString *nonFragmentURL = [request.URL.absoluteString stringByReplacingOccurrencesOfString:[@"#" stringByAppendingString:request.URL.fragment] withString:@""];
        if (webView.URL.fragment) {
            NSString *nonFragmentMainURL = [webView.URL.absoluteString stringByReplacingOccurrencesOfString:[@"#" stringByAppendingString:webView.URL.fragment] withString:@""];
            if ([nonFragmentURL isEqualToString:nonFragmentMainURL] && ![webView.URL.fragment isEqualToString:request.URL.fragment]) {
                isFragmentJump = YES;
            }
        }
        else
        {
            isFragmentJump = [nonFragmentURL isEqualToString:webView.URL.absoluteString];
        }
    }
    return isFragmentJump;
}

#pragma mark -
#pragma mark BrowserWebViewDelegate

- (BOOL)browserWebView:(BrowserWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    if ([request.URL.path isEqualToString:completeRPCURLPath]) {
        [self completeProgress];
        return NO;
    }
    
    BOOL ret = YES;
    if ([_webViewProxyDelegate respondsToSelector:@selector(browserWebView:shouldStartLoadWithRequest:navigationType:)]) {
        ret = [_webViewProxyDelegate browserWebView:webView shouldStartLoadWithRequest:request navigationType:navigationType];
    }
    
    BOOL isFragmentJump = [self isFragmentJumpWithWKWebView:webView request:request];

    BOOL isTopLevelNavigation = [request.mainDocumentURL isEqual:request.URL];

    BOOL isHTTPOrLocalFile = [request.URL.scheme isEqualToString:@"http"] || [request.URL.scheme isEqualToString:@"https"] || [request.URL.scheme isEqualToString:@"file"];
    if (ret && !isFragmentJump && isHTTPOrLocalFile && isTopLevelNavigation) {
        _currentURL = request.URL;
        [self reset];
    }
    return ret;
}

- (void)browserWebViewDidStartLoad:(BrowserWebView *)webView
{
    if ([_webViewProxyDelegate respondsToSelector:@selector(browserWebViewDidStartLoad:)]) {
        [_webViewProxyDelegate browserWebViewDidStartLoad:webView];
    }

    _loadingCount++;
    _maxLoadCount = fmax(_maxLoadCount, _loadingCount);

    [self startProgress];
}

- (void)browserWebViewDidFinishLoad:(BrowserWebView *)webView
{
    if ([_webViewProxyDelegate respondsToSelector:@selector(browserWebViewDidFinishLoad:)]) {
        [_webViewProxyDelegate browserWebViewDidFinishLoad:webView];
    }
    _loadingCount--;
    [self incrementProgress];
    WEAK_REF(self)
    [webView evaluateJavaScript:@"document.readyState" completionHandler:^(NSString * readyState, NSError * error) {
        STRONG_REF(self_)
        if (self__){
            [self__ webViewDidFinishLoad:webView readyState:readyState];
        }
    }];
}

- (void)browserWebView:(BrowserWebView *)webView didFailLoadWithError:(NSError *)error
{
    if ([_webViewProxyDelegate respondsToSelector:@selector(browserWebView:didFailLoadWithError:)]) {
        [_webViewProxyDelegate browserWebView:webView didFailLoadWithError:error];
    }
    
    _loadingCount--;
    [self incrementProgress];
    WEAK_REF(self)
    [webView evaluateJavaScript:@"document.readyState" completionHandler:^(NSString * readyState, NSError * error) {
        STRONG_REF(self_)
        if (self__){
            [self__ webView:webView didFailLoadWithError:error readyState:readyState];
        }
    }];
}

- (void)webViewDidFinishLoad:(WKWebView *)webView readyState:(NSString *)readyState{
    
    BOOL interactive = [readyState isEqualToString:@"interactive"];
    if (interactive) {
        _interactive = YES;
        NSString *waitForCompleteJS = [NSString stringWithFormat:@"window.addEventListener('load',function() { var iframe = document.createElement('iframe'); iframe.style.display = 'none'; iframe.src = '%@://%@%@'; document.body.appendChild(iframe);  }, false);", webView.URL.scheme, webView.URL.host, completeRPCURLPath];
        [webView evaluateJavaScript:waitForCompleteJS completionHandler:^(NSString * readyState, NSError * error) {
            
        }];
    }
    
    BOOL isNotRedirect = YES;
    //remove fragment
    if (_currentURL && _currentURL.fragment) {
        NSString *nonFragmentURL = [_currentURL.absoluteString stringByReplacingOccurrencesOfString:[@"#" stringByAppendingString:_currentURL.fragment] withString:@""];
        NSString *nonFragmentMainURL = webView.URL.absoluteString;
        if (webView.URL.fragment){
            nonFragmentMainURL = [webView.URL.absoluteString stringByReplacingOccurrencesOfString:[@"#" stringByAppendingString:webView.URL.fragment] withString:@""];
        }
        isNotRedirect = [nonFragmentMainURL isEqualToString:nonFragmentURL];
    }
    BOOL complete = [readyState isEqualToString:@"complete"];
    if (complete && isNotRedirect) {
        [self completeProgress];
    }
}

- (void)webView:(WKWebView *)webView didFailLoadWithError:(NSError *)error readyState:(NSString *)readyState{
    BOOL interactive = [readyState isEqualToString:@"interactive"];
    if (interactive) {
        _interactive = YES;
        NSString *waitForCompleteJS = [NSString stringWithFormat:@"window.addEventListener('load',function() { var iframe = document.createElement('iframe'); iframe.style.display = 'none'; iframe.src = '%@://%@%@'; document.body.appendChild(iframe);  }, false);", webView.URL.scheme, webView.URL.host, completeRPCURLPath];
        [webView evaluateJavaScript:waitForCompleteJS completionHandler:^(NSString * readyState, NSError * error) {
            
        }];
    }
    
    BOOL isNotRedirect = _currentURL && [_currentURL isEqual:webView.URL];
    BOOL complete = [readyState isEqualToString:@"complete"];
    if ((complete && isNotRedirect) || error) {
        [self completeProgress];
    }
}

#pragma mark -
#pragma mark Method Forwarding
// for future UIWebViewDelegate impl

- (BOOL)respondsToSelector:(SEL)aSelector
{
    if ( [super respondsToSelector:aSelector] )
        return YES;
    
    if ([self.webViewProxyDelegate respondsToSelector:aSelector])
        return YES;
    
    return NO;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
{
    NSMethodSignature *signature = [super methodSignatureForSelector:selector];
    if(!signature) {
        if([_webViewProxyDelegate respondsToSelector:selector]) {
            return [(NSObject *)_webViewProxyDelegate methodSignatureForSelector:selector];
        }
    }
    return signature;
}

- (void)forwardInvocation:(NSInvocation*)invocation
{
    if ([_webViewProxyDelegate respondsToSelector:[invocation selector]]) {
        [invocation invokeWithTarget:_webViewProxyDelegate];
    }
}

@end
