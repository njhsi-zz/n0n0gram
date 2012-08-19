// J0hn X.

#import <Foundation/Foundation.h>

typedef unsigned char nng_cell;
#define nng_BLANK  '\00'
#define nng_DOT    '\01'
#define nng_SOLID  '\02'
#define nng_BOTH   '\03'

@interface RWNngSolver : NSObject {
    
    
}

/**
 check if it's solvable.
 */
//-(BOOL) checkLogicallySolvable;

/**
 solve a puzzle
 */

-(id) initWithGrid:(NSString*)grid Width:(int) width Height:(int)height;

-(BOOL) solveOutGrid:(char*)g;

@end
