// J0hn X.

#import <Foundation/Foundation.h>

enum {NNG_L=51};

typedef unsigned char nng_cell;
#define nng_BLANK  '\00'
#define nng_DOT    '\01'
#define nng_SOLID  '\02'
#define nng_BOTH   '\03'

#define CUSTOM_FLAG 1 /// <------------  !!

@interface RWNngSolver : NSObject {
    int _solutions_sum;     
}

/**
 grid is a char image of nng_BLANK&DOT, correspondant to your picture.
 */
-(id) initWithGrid:(NSString*)grid Width:(int) width Height:(int)height;

/**
 solve the loaded puzzle to output a char image of nng_SOLD&BLANK...
 */
-(BOOL) solveOutGrid:(char*)g;


#if CUSTOM_FLAG
/**
 @puzzle: string of the image grid of N*N numbers with no linebreak, yes, N*N that width==height!
          numbers that bigger than 0 are SOLD, otherwise, as DOT.
 @example:
 ...
 RWNngSolver* s = [[RWNngSolver alloc] init];
 BOOL bsolvable = [s puzzleIsLogicallySolvable:puzzle];
 [s release];
 ... 
 */
- (BOOL)puzzleIsLogicallySolvable:(NSString *)puzzle;
#endif

@end
