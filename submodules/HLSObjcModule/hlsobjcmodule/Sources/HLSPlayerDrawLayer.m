//
//  HLSPlayerDrawLayer.m
//  HLSObjcModule
//
//  Created byVlad on 22.10.2024.
//

#import <HLSObjcModule/HLSPlayerDrawLayer.h>

@implementation HLSPlayerDrawLayer {
    HLSDecoderVideoFrame *frame;
}

- (void)drawFrame:(HLSDecoderVideoFrame *)_frame {
    if (frame != NULL) {
        frame = NULL;
    }
    
    frame = _frame;
    [self setNeedsDisplay];
}

// I know taht draw works on CPU but I'm not really familar with Metal or OpenGL... actually I've tried 
- (void)drawCGImage:(CGImageRef)image inContext:(CGContextRef)context {
    if (image != NULL && context != NULL) {
        CGSize originalSize = CGSizeMake(CGImageGetWidth(image), CGImageGetHeight(image));
        CGFloat widthRatio = self.bounds.size.width / originalSize.width;
        CGFloat heightRatio = self.bounds.size.height / originalSize.height;
        CGFloat scaleFactor = MIN(widthRatio, heightRatio);
        CGSize newSize = CGSizeMake(originalSize.width * scaleFactor, originalSize.height * scaleFactor);
        
        CGContextSaveGState(context);
        CGContextTranslateCTM(context, 0, newSize.height);
        CGContextScaleCTM(context, 1.0, -1.0);
        
        CGRect drawingRect = CGRectMake((self.bounds.size.width - newSize.width) * 0.5,
                                        -(self.bounds.size.height - newSize.height) * 0.5,
                                        newSize.width, newSize.height);
        CGContextDrawImage(context, drawingRect, image);
    }
}

//- (void)drawInContext:(CGContextRef)context {
//    @autoreleasepool {
//        [self drawCGImage:frame.cgImage inContext:context];
//        frame = NULL;
//    }
//}

@end
