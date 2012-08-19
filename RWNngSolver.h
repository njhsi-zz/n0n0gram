// J0hn X.

#import <Foundation/Foundation.h>

typedef unsigned char nonogram_cell;
#define nonogram_BLANK  '\00'
#define nonogram_DOT    '\01'
#define nonogram_SOLID  '\02'
#define nonogram_BOTH   '\03'

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
