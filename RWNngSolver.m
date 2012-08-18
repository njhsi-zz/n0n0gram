

#import "RWNngSolver.h"

/// internal

typedef unsigned char nonogram_cell;
#define nonogram_BLANK  '\00'
#define nonogram_DOT    '\01'
#define nonogram_SOLID  '\02'
#define nonogram_BOTH   '\03'

typedef unsigned long nonogram_sizetype;
#define nonogram_PRIuSIZE "lu"
#define nonogram_PRIoSIZE "lo"
#define nonogram_PRIxSIZE "lx"
#define nonogram_PRIXSIZE "lX"

typedef struct nonogram_puzzle nonogram_puzzle;

enum { /* return codes for runxxx calls */
    nonogram_UNLOADED = 0,
    nonogram_FINISHED = 1,
    nonogram_UNFINISHED = 2,
    nonogram_FOUND = 4,
    nonogram_LINE = 8
};

enum {
    nonogram_EMPTY,   /* processing, but not on line */
    nonogram_WORKING, /* currently on a line */
    nonogram_DONE     /* line processing completed */
};



struct nonogram_point { size_t x, y; };
struct nonogram_rect { struct nonogram_point min, max; };

typedef unsigned int nonogram_level;


/* greatest dimensions of the puzzle */
struct nonogram_lim {
size_t maxline, maxrule;
};

/* size of each allocated block of shared workspace */
struct nonogram_req {
size_t byte, ptrdiff, size, nonogram_size, cell;
};

/* pointers to each block of shared workspace */
struct nonogram_ws {
void *byte;
ptrdiff_t *ptrdiff;
size_t *size;
nonogram_sizetype *nonogram_size;
nonogram_cell *cell;
};

struct nonogram_initargs {
int *fits;
const nonogram_sizetype *rule;
const nonogram_cell *line;
nonogram_cell *result;
size_t linelen, rulelen;
ptrdiff_t linestep, rulestep, resultstep;
};

typedef void nonogram_prepproc(void *, const struct nonogram_lim *,
struct nonogram_req *);
typedef int nonogram_initproc(void *, struct nonogram_ws *ws,
const struct nonogram_initargs *);
typedef int nonogram_stepproc(void *, void *ws);
typedef void nonogram_termproc(void *);

/* init and step return true if step should be called (again) */
struct nonogram_linesuite {
nonogram_prepproc *prep; /* indicate workspace requirements */
nonogram_initproc *init; /* initialise for a particular line */
nonogram_stepproc *step; /* perform a single step */
nonogram_termproc *term; /* terminate line-processing */
};



typedef struct {
    int score, dot, solid;
} nonogram_lineattr;


typedef struct nonogram_stack {
struct nonogram_stack *next;
nonogram_cell *grid;
struct nonogram_rect editarea;
struct nonogram_point pos;
nonogram_lineattr *rowattr, *colattr;
int remcells, level;
} nonogram_stack;

struct nonogram_lsnt {
void *context;
const char *name;
const struct nonogram_linesuite *suite;
};

struct nonogram_rule {
size_t len;
nonogram_sizetype *val;
};


struct nonogram_puzzle {
struct nonogram_rule *row, *col;
size_t width, height;

};

typedef unsigned char nonogram_bool;

static void makescore(nonogram_lineattr *attr,
                      const struct nonogram_rule *rule, int len){
    size_t relem;
    
    attr->score = 0;
    for (relem = 0; relem < rule->len; relem++)
        attr->score += rule->val[relem];
    attr->dot = len - (attr->solid = attr->score);
    if (!attr->solid)
        attr->score = len;
    else {
        attr->score *= rule->len + 1;
        attr->score += rule->len * (rule->len - len - 1);
    }
}

/*line: fcomp*/
static void fcomp_prep(void *, const struct nonogram_lim *, struct nonogram_req *);
static int fcomp_init(void *, struct nonogram_ws *ws,
                const struct nonogram_initargs *a);
static int fcomp_step(void *, void *ws);
static const struct nonogram_linesuite nonogram_fcompsuite = {&fcomp_prep, &fcomp_init, &fcomp_step, 0 };


/// ext
@interface RWNngSolver (/* class extension */) {
 @private /* vars */
    struct nonogram_rect _editarea; /* temporary workspace */
    
    struct nonogram_ws _workspace;
    struct nonogram_lsnt _linesolver[5]; /* an array of length 'levels' */
    nonogram_level _levels;
    
    nonogram_cell _first; /* configured first guess; should be                                                                                                
                          replaced with choice based on remaining                                                                                        
                          unaccounted cells */
    int _cycles; /* could be part of complete context */
    
    const nonogram_puzzle *_puzzle;
    struct nonogram_lim _lim;
    nonogram_cell *_work;
    nonogram_lineattr *_rowattr, *_colattr;
    nonogram_level *_rowflag, *_colflag;
    
    nonogram_bool *_rowdir, *_coldir; /* to be removed */
    
    nonogram_stack *_stack; /* pushed guesses */
    nonogram_cell *_grid;
    int _remcells, _reminfo;
    /* (on_row,lineno) == line being solved */
    /* status == EMPTY => no line */
    /* status == WORKING => line being solved */
    /* status == DONE => line solved */
    /* focus => used by display */
    int _fits, _lineno;
    nonogram_level _level;
    unsigned _on_row : 1, _focus : 1, _status : 2, _reversed : 1, _alloc : 1;
    
    /* logfile */

}

/* private methods */

-(void)gatherSolvers;

-(BOOL)loadPuzzle:(nonogram_puzzle*)p Grid:(nonogram_cell *)g Remcells:(int)rc;

//-(BOOL)setLineSolver:(const struct nonogram_linesuite *)s conf:(void*)conf level:(nonogram_level) lvl;

-(int)runSolverN:(int*) tries;

-(int)runLines:(int*)lines Test:(int (*)(void*)) test Data:(void*)data;


-(int)runCycles:(void*)data Test:(int (*)(void*)) test ;

-(void)guess;

-(void)findMinRect:(struct nonogram_rect *)b;

-(void)findEasiest;

-(void)setupStep;

-(void)step;

-(int)redeemStep;

-(void)redrawRangeFrom:(int) from To:(int) to;

-(void)focusRowLine:(int)lineno Value:(int)v;
-(void)focusColLine:(int)lineno Value:(int)v;
-(void)mark1Col:(int)lineno;
-(void)mark1Row:(int)lineno;
-(void)markFrom:(int)from To:(int)to;


@end // ext i/f

/// impl
@implementation RWNngSolver



-(id)init {
    self = [super init];
    if (self) {
        /* these can get stuffed; nah, maybe not */
        _reversed = false;
        _first = nonogram_SOLID;
        _cycles = 50;
        
        /* no puzzle loaded */
        _puzzle = NULL;
        
        /* no display */
        ///  _display = NULL;                                                                                                                                 
        
        /* no place to send solutions */
        ///  _client = NULL;                                                                                                                                  

        /* no internal workspace */
        _work = NULL;
        _rowattr = _colattr = NULL;
        _rowflag = _colflag = NULL;
        _stack = NULL;
        
        /* start with no linesolvers */
        //levels = 0;
        //linesolver = NULL;
        _workspace.byte = NULL;
        _workspace.ptrdiff = NULL;
        _workspace.size = NULL;
        _workspace.nonogram_size = NULL;
        _workspace.cell = NULL;
        
        /* then add the default */
        //nonogram_setlinesolvers(c, 1);
        //nonogram_setlinesolver(c, 1, "fcomp", &nonogram_fcompsuite, 0);
        _linesolver[0].name="fcomp";
        _linesolver[0].suite = &nonogram_fcompsuite;
        _linesolver[0].context = NULL;
        _levels = 1;
        
        
        _focus = false;

    }
    
    return self;
}

-(void)dealloc {
    
    
}

-(void) gatherSolvers {
    static struct nonogram_req zero;
    struct nonogram_req most = zero, req;
    nonogram_level n;
    
    for (n = 0; n < _levels; n++)
        if (_linesolver[n].suite && _linesolver[n].suite->prep) {
            req = zero;
            (*_linesolver[n].suite->prep)(_linesolver[n].context, &_lim, &req);
            if (req.byte > most.byte)
                most.byte = req.byte;
            if (req.ptrdiff > most.ptrdiff)
                most.ptrdiff = req.ptrdiff;
            if (req.size > most.size)
                most.size = req.size;
            if (req.nonogram_size > most.nonogram_size)
                most.nonogram_size = req.nonogram_size;
            if (req.cell > most.cell)
                most.cell = req.cell;
        }
    
    free(_workspace.byte);
    free(_workspace.ptrdiff);
    free(_workspace.size);
    free(_workspace.nonogram_size);
    free(_workspace.cell);
    _workspace.byte = malloc(most.byte);
    _workspace.ptrdiff = malloc(most.ptrdiff * sizeof(ptrdiff_t));
    _workspace.size = malloc(most.size * sizeof(size_t));
    _workspace.nonogram_size =
    malloc(most.nonogram_size * sizeof(nonogram_sizetype));
    _workspace.cell = malloc(most.cell * sizeof(nonogram_cell));
}


-(BOOL)loadPuzzle:(nonogram_puzzle*)p Grid:(nonogram_cell *)g Remcells:(int)rc {
    /* local iterators */
    size_t lineno;
    
    /* is there already a puzzle loaded */
    if (_puzzle || !p)        return FALSE;    
    _puzzle = p;
    
    _lim.maxline =  (_puzzle->width > _puzzle->height) ? _puzzle->width : _puzzle->height;
    _lim.maxrule = 0;
    
    /* initialise the grid */
    _grid = g;
    _remcells = rc;
    
    /* working data */
    free(_work);
    free(_rowflag);
    free(_colflag);
    free(_rowattr);
    free(_colattr);
    _work = malloc(sizeof(nonogram_cell) * _lim.maxline);
    _rowflag = malloc(sizeof(nonogram_level) * _puzzle->height);
    _colflag = malloc(sizeof(nonogram_level) * _puzzle->width);
    _rowattr = malloc(sizeof(nonogram_lineattr) * _puzzle->height);
    _colattr = malloc(sizeof(nonogram_lineattr) * _puzzle->width);
    _reminfo = 0;
    _stack = NULL;
    
    /* determine heuristic scores for each column */
    for (lineno = 0; lineno < _puzzle->width; lineno++) {
        struct nonogram_rule *rule = _puzzle->col + lineno;
        
        _reminfo += !!(_colflag[lineno] = _levels);
        
        if (rule->len > _lim.maxrule)
            _lim.maxrule = rule->len;
        
        makescore(_colattr + lineno, rule, _puzzle->height);
    }
    
    /* determine heuristic scores for each row */
    for (lineno = 0; lineno < _puzzle->height; lineno++) {
        struct nonogram_rule *rule = _puzzle->row + lineno;
        
        _reminfo += !!(_rowflag[lineno] = _levels);
        
        if (rule->len > _lim.maxrule)
            _lim.maxrule = rule->len;
        
        makescore(_rowattr + lineno, rule, _puzzle->width);
    }
    
    [self gatherSolvers];
    
    /* configure line solver */
    _status = nonogram_EMPTY;
    
    return TRUE;
   
}

static int nonogram_testtries(void *vt)
{
    int *tries = vt;
    return (*tries)-- > 0;
}

-(int)runSolverN:(int*) tries {
    int cy = _cycles;
    
    int r = [self runLines:tries Cycles:&cy];
    
    return r == nonogram_LINE ? nonogram_UNFINISHED : r; 
}

-(int)runLines:(int *)lines Cycles:(int *)cycles {
    
    int r = _puzzle ? nonogram_UNFINISHED : nonogram_UNLOADED;
    
    while (*lines > 0) {
        if ((r = [self runCycles:cycles Test:&nonogram_testtries]) == nonogram_LINE)
            --*lines;
        else
            return r;
    }
    return r;
    
}

-(int)runCycles:(void*)data Test:(int (*)(void*)) test  {
    if (!_puzzle) {
        return nonogram_UNLOADED;
    } else if (_status == nonogram_WORKING) {
        /* in the middle of solving a line */
        while ((*test)(data) && _status == nonogram_WORKING)
            [self step];
        return nonogram_UNFINISHED;
    } else if (_status == nonogram_DONE)  {
        /* a line is solved, but not acted upon */
        size_t linelen;
        
        /* indicate end of line-processing */
        if (_on_row)
            [self focusRowLine:_lineno Value:0], linelen = _puzzle->width;
        else
            [self focusColLine:_lineno Value:0], linelen = _puzzle->height;
        
        
        /* test for consistency */
        if (_fits == 0) {
            /* nothing fitted; must be an error */
            _remcells = -1;
        } else {
            int changed;
            
            
            /* update display and count number of changed cells and flags */
            changed = [self redeemStep];
            
            /* indicate choice to display */
            if (_on_row) {
                if (_rowattr[_lineno].dot == 0 &&
                    _rowattr[_lineno].solid == 0)
                    _rowflag[_lineno] = 0;
                else if (_fits < 0 && changed)
                    _rowflag[_lineno] = _levels;
                else
                    --_rowflag[_lineno];
                if (!_rowflag[_lineno]) _reminfo--;
                [self mark1Row:_lineno];
            } else {
                if (_colattr[_lineno].dot == 0 &&
                    _colattr[_lineno].solid == 0)
                    _colflag[_lineno] = 0;
                else if (_fits < 0 && changed)
                    _colflag[_lineno] = _levels;
                else
                    --_colflag[_lineno];
                if (!_colflag[_lineno]) _reminfo--;
                [self mark1Col:_lineno];
            }
        }
        
        
        /* set state to indicate no line currently chosen */
        _status = nonogram_EMPTY;
        return nonogram_LINE;
    } else if (_remcells < 0) {
        /* back-track caused by error or completion of grid */
        nonogram_stack *st = _stack;
        
        if (st) {
            size_t y, w;
            
            /* copy from stack */
            _remcells = st->remcells;
            _reminfo = 0;
            
            
            
            w = st->editarea.max.x - st->editarea.min.x;
            for (y = st->editarea.min.y; y < st->editarea.max.y; y++)
                memcpy(_grid + st->editarea.min.x + y * _puzzle->width,
                       st->grid + (y - st->editarea.min.y) * w, w);
            
            /* update screen with restored data */
            ///if (_display && _display->redrawarea)  (*_display->redrawarea)(_display_data, &st->editarea);
            /* mark rows and cols (from st->editarea) as unflagged */
            _reversed = false;
            for (y = st->editarea.min.x; y < st->editarea.max.x; y++) {
                _colflag[y] = false;
                
                /* also restore scores */
                _colattr[y] = st->colattr[y - st->editarea.min.x];
            }
            ///if (_display && _display->colmark)  (*_display->colmark)(_display_data, st->editarea.min.x, st->editarea.max.x);
            for (y = st->editarea.min.y; y < st->editarea.max.y; y++) {
                _rowflag[y] = false;
                
                /* also restore scores */
                _rowattr[y] = st->rowattr[y - st->editarea.min.y];
            }
            /// if (_display && _display->rowmark)        (*_display->rowmark)(_display_data,st->editarea.min.y, st->editarea.max.y);
            
            if (~st->level & nonogram_BOTH) {
                /* make subsequent guess */
                [self guess];  
            } else {
                /* pull from stack */
                
                _stack = st->next;
                free(st->grid);
                free(st->rowattr);
                free(st->colattr);
                free(st);
                _remcells = -1;
            }
            return nonogram_LINE;
            /* finished loading from stack */
        } else {
            /* nothing left on stack - stop */
            return nonogram_FINISHED;
        }
        /* back-tracking dealt with */
    } else if (_reminfo > 0) {
        /* no errors, but there are still lines to test */
        [self findEasiest];
        
        /* set up context for solving a row or column */
        if (_on_row) {
            
            _editarea.max.y = (_editarea.min.y = _lineno) + 1;
            [self focusRowLine:_lineno Value:1];
        } else {
            
            _editarea.max.x = (_editarea.min.x = _lineno) + 1;
            [self focusColLine:_lineno Value:1]; 

        }
        [self setupStep];
        /* a line still to be tested has now been set up for solution */
        return nonogram_UNFINISHED;
    } else if (_remcells == 0) {
        /* no remaining lines or cells; no error - must be solution */
        
        /// if (_client && _client->present) (*_client->present)(_client_data);
        printf("client printit\n");
        
        _remcells = -1;
        return _stack ? nonogram_FOUND : nonogram_FINISHED;
    } else {
        /* no more info; no errors; some cells left
         - push stack to make a guess */
        nonogram_stack *st;
        size_t x, y, w, h;
        
        /* record the current state */
        /* create and insert new stack element */
        
        st = malloc(sizeof(nonogram_stack));
        st->next = _stack;
        _stack = st;
        st->remcells = _remcells;
        st->level = nonogram_BLANK;
        
        /* find area to be recorded */
#if nonogram_PUSHALL
        /* COP-OUT: just use whole area */
        st->editarea.min.x = st->editarea.min.y = 0;
        st->editarea.max.x = _puzzle->width;
        st->editarea.max.y = _puzzle->height;
#else
        /* be more selective */
        [self findMinRect:&st->editarea];
#endif
        w = st->editarea.max.x - st->editarea.min.x;
        h = st->editarea.max.y - st->editarea.min.y;
        
        
        /* copy specified area */
        st->grid = malloc(w * h * sizeof(nonogram_cell));
        for (y = st->editarea.min.y; y < st->editarea.max.y; y++)
            memcpy(st->grid + (y - st->editarea.min.y) * w,
                   _grid + st->editarea.min.x + y * _puzzle->width, w);
        
        /* copy scores */
        st->rowattr = malloc(h * sizeof(nonogram_lineattr));
        st->colattr = malloc(w * sizeof(nonogram_lineattr));
        for (y = st->editarea.min.y; y < st->editarea.max.y; y++)
            st->rowattr[y - st->editarea.min.y] = _rowattr[y];
        for (x = st->editarea.min.x; x < st->editarea.max.x; x++)
            st->colattr[x - st->editarea.min.x] = _colattr[x];
        
        /* choose position to make guess */
        {
            int bestscore = -1000;
            for (x = st->editarea.min.x; x < st->editarea.max.x; x++)
                for (y = st->editarea.min.y; y < st->editarea.max.y; y++)
                    if (_grid[x + y * _puzzle->width] == nonogram_BLANK) {
                        int score = _rowattr[y].score + _colattr[x].score;
                        if (score < bestscore)
                            continue;
                        bestscore = score;
                        st->pos.x = x;
                        st->pos.y = y;
                    }
        }
        
        [self guess];
        return nonogram_LINE;
    }
    
    return nonogram_UNFINISHED;
}

-(void)focusRowLine:(int)lineno Value:(int)v { _focus = v;}
-(void)focusColLine:(int)lineno Value:(int)v { _focus = v;}
-(void)mark1Col:(int)lineno {}
-(void)mark1Row:(int)lineno {}
-(void)markFrom:(int)from To:(int)to {}

-(int)redeemStep {
    int changed = 0;
    nonogram_cell *line;
    nonogram_sizetype *rule;
    size_t linelen, rulelen, perplen;
    ptrdiff_t linestep, flagstep, rulestep;
    nonogram_lineattr *attr, *rattr, *cattr;
    nonogram_level *flag;
    
    size_t i;
    
    struct {
        int from;
        unsigned inrange : 1;
    } cells = { 0, false }, flags = { 0, false };
    
    if (_on_row) {
        line = _grid + _puzzle->width * _lineno;
        linelen = _puzzle->width;
        linestep = 1;
        rule = _puzzle->row[_lineno].val;
        rulelen = _puzzle->row[_lineno].len;
        rulestep = 1;
        perplen = _puzzle->height;
        rattr = _colattr;
        cattr = _rowattr + _lineno;
        flag = _colflag;
        flagstep = 1;
    } else {
        line = _grid + _lineno;
        linelen = _puzzle->height;
        linestep = _puzzle->width;
        rule = _puzzle->col[_lineno].val;
        rulelen = _puzzle->col[_lineno].len;
        rulestep = 1;
        perplen = _puzzle->width;
        cattr = _colattr + _lineno;
        rattr = _rowattr;
        flag = _rowflag;
        flagstep = 1;
    }
    
    for (i = 0; i < linelen; i++)
        switch (line[i * linestep]) {
            case nonogram_BLANK:
                switch (_work[i]) {
                    case nonogram_DOT:
                    case nonogram_SOLID:
                        changed = 1;
                        if (!cells.inrange) {
                            cells.from = i;
                            cells.inrange = true;
                        }
                        line[i * linestep] = _work[i];
                        _remcells--;
                        
                        /* update score for perpendicular line */
                        attr = &rattr[i * flagstep];
                        if (!--*(_work[i] == nonogram_DOT ?
                                 &attr->dot : &attr->solid))
                            attr->score = perplen;
                        else
                            attr->score++;
                        
                        /* update score for solved line */
                        if (!--*(_work[i] == nonogram_DOT ? &cattr->dot : &cattr->solid))
                            cattr->score = linelen;
                        else
                            cattr->score++;
                        
                        if (flag[i * flagstep] < _levels) {
                            if (flag[i * flagstep] == 0) _reminfo++;
                            flag[i * flagstep] = _levels;
                            
                            if (!flags.inrange) {
                                flags.from = i;
                                flags.inrange = true;
                            }
                        } else if (flags.inrange) {
                            [self markFrom:flags.from To:i];
                            flags.inrange = false;
                        }
                        break;
                }
                break;
            default:
                if (cells.inrange) {
                    [self redrawRangeFrom:cells.from To:i];
                    cells.inrange = false;
                }
                if (flags.inrange) {
                    [self markFrom:flags.from To:i];
                    flags.inrange = false;
                }
                break;
        }
    if (cells.inrange) {
        [self redrawRangeFrom:cells.from To:i];
        cells.inrange = false;
    }
    if (flags.inrange) {
        [self markFrom:flags.from To:i];
        flags.inrange = false;
    }
    
    if (_level <= _levels && _level > 0 &&
        _linesolver[_level - 1].suite &&
        _linesolver[_level - 1].suite->term)
        (*_linesolver[_level - 1].suite->term)
        (_linesolver[_level - 1].context);
    
    return changed;
}

-(void)guess {
    nonogram_stack *st = _stack;
    int guess;
    
    if (!st) return;
    
#if false
#if 0
    /* make guess */
    guess = st->level ? (nonogram_BOTH ^ st->level): _first;
#else
    /* hard-wired first choice */
#if 1
    /* dot first */
    guess = (st->level & nonogram_DOT) ? nonogram_SOLID : nonogram_DOT;
#else
    /* solid first */
    guess = (st->level & nonogram_SOLID) ? nonogram_DOT : nonogram_SOLID;
#endif
#endif
#else
    /* guess base on majority of unaccounted cells */
    guess = st->level ? (nonogram_BOTH ^ st->level) :
    (_rowattr[st->pos.y].dot + _colattr[st->pos.x].dot >
     _rowattr[st->pos.y].solid + _colattr[st->pos.x].solid ?
     nonogram_DOT : nonogram_SOLID);
#endif
    
    
    _grid[st->pos.x + st->pos.y * _puzzle->width] = guess;
    
    /* update score for row */
    if (!--*(guess == nonogram_DOT ?
             &_rowattr[st->pos.y].dot : &_rowattr[st->pos.y].solid))
        _rowattr[st->pos.y].score = _puzzle->height;
    else
        _rowattr[st->pos.y].score++;
    
    /* update score for column */
    if (!--*(guess == nonogram_DOT ?
             &_colattr[st->pos.x].dot : &_colattr[st->pos.x].solid))
        _colattr[st->pos.x].score = _puzzle->width;
    else
        _colattr[st->pos.x].score++;
    
    st->level |= guess;
    _remcells--;
    _reminfo = 2;
    
    _rowflag[st->pos.y] = _levels;
    _colflag[st->pos.x] = _levels;
    [self mark1Row:st->pos.y];
    [self mark1Col:st->pos.x];
}

-(void)findMinRect:(struct nonogram_rect *)b {
    int m = _puzzle->width * _puzzle->height;
    int first = 0, last = m - 1;
    size_t x, y;
    
    if (_puzzle->width == 0 || _puzzle->height == 0) {
        b->min.x = b->min.y = 0;
        b->max.x = _puzzle->width;
        b->max.y = _puzzle->height;
        return;
    }
    
    while (first < m && _grid[first] != nonogram_BLANK)
        first++;
    b->min.x = first % _puzzle->width;
    b->min.y = first / _puzzle->width;
    for (y = b->min.y + 1; y < _puzzle->height; y++) {
        for (x = 0; x < b->min.x &&
             _grid[x + y * _puzzle->width] != nonogram_BLANK; x++)
            ;
        b->min.x = x;
    }
    
    while (last >= first && _grid[last] != nonogram_BLANK)
        last--;
    b->max.x = last % _puzzle->width + 1;
    b->max.y = last / _puzzle->width + 1;
    for (y = b->max.y; y > b->min.y; ) {
        y--;
        for (x = _puzzle->width; x > b->max.x; ) {
            x--;
            if (_grid[x + y * _puzzle->width] == nonogram_BLANK) {
                x++;
                break;
            }
        }
        b->max.x = x;
    }
    
}

-(void)findEasiest {
    int score;
    size_t i;
    
    _level = _rowflag[0];
    score = _rowattr[0].score;
    _on_row = true;
    _lineno = 0;
    
    for (i = 0; i < _puzzle->height; i++)
        if (_rowflag[i] > _level ||
            (_level > 0 && _rowflag[i] == _level &&
             _rowattr[i].score > score)) {
                _level = _rowflag[i];
                score = _rowattr[i].score;
                _lineno = i;
            }
    
    for (i = 0; i < _puzzle->width; i++)
        if (_colflag[i] > _level ||
            (_level > 0 && _colflag[i] == _level &&
             _colattr[i].score > score)) {
                _level = _colflag[i];
                score = _colattr[i].score;
                _lineno = i;
                _on_row = false;
            }
}


-(void)setupStep {
    struct nonogram_initargs a;
    const char *name;
    
    if (_on_row) {
        a.line = _grid + _puzzle->width * _lineno;
        a.linelen = _puzzle->width;
        a.linestep = 1;
        a.rule = _puzzle->row[_lineno].val;
        a.rulelen = _puzzle->row[_lineno].len;
    } else {
        a.line = _grid + _lineno;
        a.linelen = _puzzle->height;
        a.linestep = _puzzle->width;
        a.rule = _puzzle->col[_lineno].val;
        a.rulelen = _puzzle->col[_lineno].len;
    }
    a.rulestep = 1;
    a.fits = &_fits;
    ///  a.log = &_tmplog;
    a.result = _work;
    a.resultstep = 1;
    
    _reversed = false;
    
    if (_level > _levels || _level < 1 ||
        !_linesolver[_level - 1].suite ||
        !_linesolver[_level - 1].suite->init)
        name = "backup";
    else
        name = _linesolver[_level - 1].name ?
        _linesolver[_level - 1].name : "unknown";
    
    
    /* implement a backup solver */
    if (_level > _levels || _level < 1 ||
        !_linesolver[_level - 1].suite ||
        !_linesolver[_level - 1].suite->init) {
        size_t i;
        
        /* reveal nothing */
        for (i = 0; i < a.linelen; i++)
            switch (a.line[i * a.linestep]) {
                case nonogram_DOT:
                case nonogram_SOLID:
                    _work[i] = a.line[i * a.linestep];
                    break;
                default:
                    _work[i] = nonogram_BOTH;
                    break;
            }
        
        _status = nonogram_DONE;
        return;
    }
    
    _status =
    (*_linesolver[_level - 1].suite->init)
    (_linesolver[_level - 1].context, &_workspace, &a) ?
    nonogram_WORKING : nonogram_DONE;
}

-(void)step {
    if (_level > _levels || _level < 1 ||
        !_linesolver[_level - 1].suite ||
        !_linesolver[_level - 1].suite->step) {
        size_t i, linelen = _on_row ? _puzzle->width : _puzzle->height;
        ptrdiff_t linestep = _on_row ? 1 : _puzzle->width;
        const nonogram_cell *line =
        _on_row ? _grid + _puzzle->width * _lineno : _grid + _lineno;
        
        /* reveal nothing */
        for (i = 0; i < linelen; i++)
            switch (line[i * linestep]) {
                case nonogram_DOT:
                case nonogram_SOLID:
                    _work[i] = line[i * linestep];
                    break;
                default:
                    _work[i] = nonogram_BOTH;
                    break;
            }
        
        _status = nonogram_DONE;
        return;
    }
    
    _status = (*_linesolver[_level - 1].suite->step)
    (_linesolver[_level - 1].context, _workspace.byte) ?
    nonogram_WORKING : nonogram_DONE;
}

-(void) redrawRangeFrom:(int)from To:(int)to {
    if (_on_row) {
        if (_reversed) {
            _editarea.max.x = _puzzle->width - from;
            _editarea.min.x = _puzzle->width - to;
        } else {
            _editarea.min.x = from;
            _editarea.max.x = to;
        }
    } else {
        if (_reversed) {
            _editarea.max.y = _puzzle->height - from;
            _editarea.min.y = _puzzle->height - to;
        } else {
            _editarea.min.y = from;
            _editarea.max.y = to;
        }
    }
}

@end // impl
