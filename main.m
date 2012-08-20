#import <Foundation/Foundation.h>

#import "RWNngSolver.h"

int printgrid(const nng_cell *grid, size_t width, size_t height,
              const char *solid, const char *dot,
              const char *blank)
{
    size_t row, col, count = 0;
    
    for (row = 0; row < height; row++) {
        for (col = 0; col < width; col++) {
            int c = grid[col + row * width];
            
            count += printf( "%s", c == nng_SOLID ? solid :
                            c == nng_DOT ? dot : blank);
        }
        printf("|\n");
        count++;
    }
    return count;
}


int main (int argc, const char * argv[]) {
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    NSLog(@"Hello world!");


    NSString *puzzle = [[NSString alloc]    initWithUTF8String:"5550000000555000222055500025200000002220000000060000707006600007006600440700060044770006009999999999"];
    RWNngSolver* s = [[RWNngSolver alloc] init];
    
    BOOL bsolved = [s puzzleIsLogicallySolvable:puzzle];        

    if (bsolved) NSLog(@"solvable!");
    
    [pool drain];
    
    return 0;
}
