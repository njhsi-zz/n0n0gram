#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

#import "RWNngSolver.h"

nonogram_cell *loadgrid(size_t *width, size_t *height,
                        FILE *fp, char solid, char dot)
{
    struct line {
        struct line *prev;
        nonogram_cell *data;
    };
    
    char temp[300];
    nonogram_cell *result;
    size_t len, i;
    struct line *bottom;
    
    if (!width || !height) return NULL;
    bottom = NULL;
    *width = 0;
    *height = 0;
    
    while (fgets(temp, sizeof temp, fp)) {
        struct line *next;
        
        len = strlen(temp);
        if (len > 0 && temp[len - 1] == '\n')
            temp[--len] = '\0';
        
        if (*width < 1) {
            *width = len;
        } else if (len != *width) {
            goto finished;
        }
        
        next = malloc(sizeof(struct line));
        if (!next)
            goto failure;
        next->data = malloc(*width * sizeof(nonogram_cell));
        if (!next->data)
            goto failure;
        for (i = 0; i < *width; i++)
            next->data[i] = temp[i] == dot ? nonogram_DOT :
            (temp[i] == solid ? nonogram_SOLID : nonogram_BLANK);
        next->prev = bottom;
        bottom = next;
        (*height)++;
    }
    
finished:
    result = ((nonogram_cell *) malloc((*width)*(*height)*sizeof(nonogram_cell)));
    if (!result)
        goto failure;
    
    for (i = *height; i > 0; ) {
        struct line *prev = bottom->prev;
        i--;
        memcpy(result + i * *width, bottom->data, *width);
        free(bottom->data);
        free(bottom);
        bottom = prev;
    }
    
    return result;
    
failure:
    while (bottom) {
        struct line *prev = bottom->prev;
        free(bottom->data);
        free(bottom);
        bottom = prev;
    }
    
    return NULL;
}



int printgrid(const nonogram_cell *grid, size_t width, size_t height,
              const char *solid, const char *dot,
              const char *blank)
{
    size_t row, col, count = 0;
    
    for (row = 0; row < height; row++) {
        for (col = 0; col < width; col++) {
            int c = grid[col + row * width];
            
            count += printf( "%s", c == nonogram_SOLID ? solid :
                            c == nonogram_DOT ? dot : blank);
        }
        printf("|\n");
        count++;
    }
    return count;
}


int main (int argc, const char * argv[]) {
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    NSLog(@"Hello world!");
    printf("printf 1\n");
    
    FILE* fgrid = fopen("/Users/j0hn/workspace/n0n0gram.git/pic.txt", "r");
    
    size_t w,h;
    nonogram_cell* g = loadgrid(&w,&h, fgrid, '#', '-');
    
    NSString* grid = [[NSString alloc] initWithUTF8String:g];
    
    RWNngSolver* s = [[RWNngSolver alloc] initWithGrid:grid Width:w Height:h];
    
    nonogram_cell* result_grid = malloc(w*h*sizeof(nonogram_cell));
    
    [s solveOutGrid:result_grid];
    
    printgrid(result_grid, w, h, "*", ".", " ");
    
    [pool drain];
    
    return 0;
}