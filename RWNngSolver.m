#import "RWNngSolver.h"

/// internal

typedef unsigned long nng_sizetype;

typedef struct nng_puzzle nng_puzzle;

enum { /* return codes for runxxx calls */
    nng_UNLOADED = 0,
    nng_FINISHED = 1,
    nng_UNFINISHED = 2,
    nng_FOUND = 4,
    nng_LINE = 8
};

enum {
    nng_EMPTY,   /* processing, but not on line */
    nng_WORKING, /* currently on a line */
    nng_DONE     /* line processing completed */
};



struct nng_point { size_t x, y; };
struct nng_rect { struct nng_point min, max; };

typedef unsigned int nng_level;


/* greatest dimensions of the puzzle */
struct nng_lim {
size_t maxline, maxrule;
};

/* size of each allocated block of shared workspace */
struct nng_req {
size_t byte, ptrdiff, size, nng_size, cell;
};

/* pointers to each block of shared workspace */
struct nng_ws {
void *byte;
ptrdiff_t *ptrdiff;
size_t *size;
nng_sizetype *nng_size;
nng_cell *cell;
};

struct nng_initargs {
int *fits;
const nng_sizetype *rule;
const nng_cell *line;
nng_cell *result;
size_t linelen, rulelen;
ptrdiff_t linestep, rulestep, resultstep;
};

typedef void nng_prepproc(void *, const struct nng_lim *,
struct nng_req *);
typedef int nng_initproc(void *, struct nng_ws *ws,
const struct nng_initargs *);
typedef int nng_stepproc(void *, void *ws);
typedef void nng_termproc(void *);

/* init and step return true if step should be called (again) */
struct nng_linesuite {
nng_prepproc *prep; /* indicate workspace requirements */
nng_initproc *init; /* initialise for a particular line */
nng_stepproc *step; /* perform a single step */
nng_termproc *term; /* terminate line-processing */
};



typedef struct {
    int score, dot, solid;
} nng_lineattr;


typedef struct nng_stack {
struct nng_stack *next;
nng_cell *grid;
struct nng_rect editarea;
struct nng_point pos;
nng_lineattr *rowattr, *colattr;
int remcells, level;
} nng_stack;

struct nng_lsnt {
void *context;
const char *name;
const struct nng_linesuite *suite;
};

struct nng_rule {
size_t len;
nng_sizetype *val;
};


struct nng_puzzle {
struct nng_rule *row, *col;
size_t width, height;

};


static void makescore(nng_lineattr *attr,
                      const struct nng_rule *rule, int len){
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

static int nng_parseline(const nng_cell *st,
                              size_t len, ptrdiff_t step,
                              nng_sizetype *v, ptrdiff_t vs)
{
    size_t i;
    int count = 0;
    int inblock = false;
    
    for (i = 0; i < len; i++)
        switch (st[i * step]) {
            case nng_DOT:
                if (inblock) {
                    inblock = false;
                    count++;
                }
                break;
            case nng_SOLID:
                if (!inblock) {
                    inblock = true;
                    if (v)
                        v[count * vs] = 0;
                }
                if (v)
                    v[count * vs]++;
                break;
            default:
                return -1;
        }
    return count + !!inblock;
}

static int nng_makepuzzle(nng_puzzle *p, const nng_cell *g,
                        size_t w, size_t h)

{
    size_t n;
    
    if (!p || !g) return -1;
    
    p->width = w;
    p->height = h;
    
    p->row = malloc(sizeof(struct nng_rule) * h);
    p->col = malloc(sizeof(struct nng_rule) * w);
    
    if (!p->row || !p->col)
        goto failure;
    
    for (n = 0; n < h; n++) {
        int rc = nng_parseline(g + w * n, w, 1, NULL, 0);
        if (rc < 0)
            goto failure;
        p->row[n].len = rc;
        p->row[n].val = NULL;
    }
    for (n = 0; n < w; n++) {
        int rc = nng_parseline(g + n, h, w, NULL, 0);
        if (rc < 0)
            goto failure;
        p->col[n].len = rc;
        p->col[n].val = NULL;
    }
    for (n = 0; n < h; n++) {
        struct nng_rule *rule = &p->row[n];
        rule->val = malloc(sizeof(nng_sizetype) * rule->len);
        if (!rule->val)
            goto worse;
        nng_parseline(g + w * n, w, 1, rule->val, 1);
    }
    for (n = 0; n < w; n++) {
        struct nng_rule *rule = &p->col[n];
        rule->val = malloc(sizeof(nng_sizetype) * rule->len);
        if (!rule->val)
            goto worse;
        nng_parseline(g + n, h, w, rule->val, 1);
    }
    return 0;
    
worse:
    for (n = 0; n < h; n++)
        free(p->row[n].val);
        for (n = 0; n < w; n++)
            free(p->col[n].val);
            failure:
            free(p->row);
            free(p->col);
            return -1;
}


/*line: fcomp*/
static void fcomp_prep(void *, const struct nng_lim *, struct nng_req *);
static int fcomp_init(void *, struct nng_ws *ws,
                const struct nng_initargs *a);
static int fcomp_step(void *, void *ws);
static const struct nng_linesuite nng_fcompsuite = {&fcomp_prep, &fcomp_init, &fcomp_step, 0 };


/// ext
@interface RWNngSolver (/* class extension */) {
 @private /* vars */
    struct nng_rect _editarea; /* temporary workspace */
    
    struct nng_ws _workspace;
    struct nng_lsnt _linesolver[5]; /* an array of length 'levels' */
    nng_level _levels;
    
    nng_cell _first; /* configured first guess; should be                                                                                                
                          replaced with choice based on remaining                                                                                        
                          unaccounted cells */
    int _cycles; /* could be part of complete context */
    
    const nng_puzzle *_puzzle;
    struct nng_lim _lim;
    nng_cell *_work;
    nng_lineattr *_rowattr, *_colattr;
    nng_level *_rowflag, *_colflag;
    
    nng_stack *_stack; /* pushed guesses */
    nng_cell *_grid;
    int _remcells, _reminfo;
    /* (on_row,lineno) == line being solved */
    /* status == EMPTY => no line */
    /* status == WORKING => line being solved */
    /* status == DONE => line solved */
    /* focus => used by display */
    int _fits, _lineno;
    nng_level _level;
    unsigned _on_row : 1, _focus : 1, _status : 2, _reversed : 1, _alloc : 1;
    
    /* logfile */

}

/* private methods */

-(void)gatherSolvers;

-(BOOL)loadPuzzle:(nng_puzzle*)p Grid:(nng_cell *)g Remcells:(int)rc;
-(void)unload;

//-(BOOL)setLineSolver:(const struct nng_linesuite *)s conf:(void*)conf level:(nng_level) lvl;

-(int)runSolverN:(int*) tries;

-(int)runLines:(int*)lines Test:(int (*)(void*)) test Data:(void*)data;

-(int)runCycles:(void*)data Test:(int (*)(void*)) test ;

-(void)guess;

-(void)findMinRect:(struct nng_rect *)b;

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




-(id)initWithGrid:(NSString *)grid Width:(int)w Height:(int)h {
    
    if (!(self=[self init ])) return self;
   
    nng_puzzle* p = malloc(sizeof(nng_puzzle));
    if (p && !nng_makepuzzle(p, [grid UTF8String], w, h) ) {
        [self loadPuzzle:p Grid:0 Remcells:w*h];
    }
   
    return self;
}

-(id)init {
    self = [super init];
    if (self) {
        /* these can get stuffed; nah, maybe not */
        _reversed = false;
        _first = nng_SOLID;
        _cycles = 50;
        
        /* no puzzle loaded */
        _puzzle = NULL;
        _solutions_sum = 0;
        
         /* no internal workspace */
        _work = NULL;
        _rowattr = _colattr = NULL;
        _rowflag = _colflag = NULL;
        _stack = NULL;
        
        /* start with no linesolvers */
        _levels = 0;
        //linesolver = NULL;
        _workspace.byte = NULL;
        _workspace.ptrdiff = NULL;
        _workspace.size = NULL;
        _workspace.nng_size = NULL;
        _workspace.cell = NULL;
        
        /* then add the default */
        _linesolver[0].name="fcomp";
        _linesolver[0].suite = &nng_fcompsuite;
        _linesolver[0].context = NULL;
        _levels = 1;

        _focus = false;

    }
    
    return self;
}

-(void)unload {
    nng_stack *st = _stack;
    
    /* cancel current linesolver */
    if (_puzzle)
        switch (_status) {
            case nng_DONE:
            case nng_WORKING:
                if (_linesolver[_level].suite->term)
                    (*_linesolver[_level].suite->term)
                    (_linesolver[_level].context);
                break;
        }
    
    /* free stack */
    while (st) {
        _stack = st->next;
        free(st->grid);
        free(st->rowattr);
        free(st->colattr);
        free(st);
        st = _stack;
    }
    _focus = false;
    _puzzle = NULL; //`` to free
    _solutions_sum = 0;
}

-(void)dealloc {
    [self unload];
    
    /* release all workspace */
    /* free(NULL) should be safe */
    free(_workspace.byte);
    free(_workspace.ptrdiff);
    free(_workspace.size);
    free(_workspace.nng_size);
    free(_workspace.cell);
    free(_rowflag);
    free(_colflag);
    free(_rowattr);
    free(_colattr);
    free(_work);
    
    [super dealloc];
}

-(BOOL)solveOutGrid:(char *)g {
    _grid = g;

    int tries = 0;
    const int sol_limit = 2;
    while (_solutions_sum<sol_limit && [self runSolverN:(tries=1,&tries)] != nng_FINISHED);
    
    return (_solutions_sum>0);
}

#if CUSTOM_FLAG


-(BOOL)puzzleIsLogicallySolvable:(NSString*)puzzle {
    
    NSMutableString* s = [[NSMutableString alloc] initWithString:puzzle];
    int slen = [s length];
    int u = sqrt(slen);
    
    if (!u || (u*u!=slen)) return FALSE;
    
    char *ps = [puzzle UTF8String];
    
    char *gs = malloc(slen*sizeof(char));
    
    int i;
    for (i=0;i<slen;i++) {
        if (ps[i]=='0') gs[i]=nng_DOT;
        else gs[i]=nng_SOLID;
    }
    
    NSString *grid = [[NSString alloc] initWithUTF8String:gs];
    
    [self initWithGrid:grid Width:u Height:u];
    
    
    BOOL bsolvable = [self solveOutGrid:gs];
    
    
    free(gs);
    
    return bsolvable;

}
#endif

-(void) gatherSolvers {
    static struct nng_req zero;
    struct nng_req most = zero, req;
    nng_level n;
    
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
            if (req.nng_size > most.nng_size)
                most.nng_size = req.nng_size;
            if (req.cell > most.cell)
                most.cell = req.cell;
        }
    
    free(_workspace.byte);
    free(_workspace.ptrdiff);
    free(_workspace.size);
    free(_workspace.nng_size);
    free(_workspace.cell);
    _workspace.byte = malloc(most.byte);
    _workspace.ptrdiff = malloc(most.ptrdiff * sizeof(ptrdiff_t));
    _workspace.size = malloc(most.size * sizeof(size_t));
    _workspace.nng_size =
    malloc(most.nng_size * sizeof(nng_sizetype));
    _workspace.cell = malloc(most.cell * sizeof(nng_cell));
}


-(BOOL)loadPuzzle:(nng_puzzle*)p Grid:(nng_cell *)g Remcells:(int)rc {
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
    _work = malloc(sizeof(nng_cell) * _lim.maxline);
    _rowflag = malloc(sizeof(nng_level) * _puzzle->height);
    _colflag = malloc(sizeof(nng_level) * _puzzle->width);
    _rowattr = malloc(sizeof(nng_lineattr) * _puzzle->height);
    _colattr = malloc(sizeof(nng_lineattr) * _puzzle->width);
    _reminfo = 0;
    _stack = NULL;
    
    /* determine heuristic scores for each column */
    for (lineno = 0; lineno < _puzzle->width; lineno++) {
        struct nng_rule *rule = _puzzle->col + lineno;
        
        _reminfo += !!(_colflag[lineno] = _levels);
        
        if (rule->len > _lim.maxrule)
            _lim.maxrule = rule->len;
        
        makescore(_colattr + lineno, rule, _puzzle->height);
    }
    
    /* determine heuristic scores for each row */
    for (lineno = 0; lineno < _puzzle->height; lineno++) {
        struct nng_rule *rule = _puzzle->row + lineno;
        
        _reminfo += !!(_rowflag[lineno] = _levels);
        
        if (rule->len > _lim.maxrule)
            _lim.maxrule = rule->len;
        
        makescore(_rowattr + lineno, rule, _puzzle->width);
    }
    
    [self gatherSolvers];
    
    /* configure line solver */
    _status = nng_EMPTY;
    
    return TRUE;
   
}

static int nng_testtries(void *vt)
{
    int *tries = vt;
    return (*tries)-- > 0;
}

-(int)runSolverN:(int*) tries {
    int cy = _cycles;
    
    int r = [self runLines:tries Cycles:&cy];
    
    return r == nng_LINE ? nng_UNFINISHED : r; 
}

-(int)runLines:(int *)lines Cycles:(int *)cycles {
    
    int r = _puzzle ? nng_UNFINISHED : nng_UNLOADED;
    
    while (*lines > 0) {
        if ((r = [self runCycles:cycles Test:&nng_testtries]) == nng_LINE)
            --*lines;
        else
            return r;
    }
    return r;
    
}

-(int)runCycles:(void*)data Test:(int (*)(void*)) test  {
    if (!_puzzle) {
        return nng_UNLOADED;
    } else if (_status == nng_WORKING) {
        /* in the middle of solving a line */
        while ((*test)(data) && _status == nng_WORKING)
            [self step];
        return nng_UNFINISHED;
    } else if (_status == nng_DONE)  {
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
        _status = nng_EMPTY;
        return nng_LINE;
    } else if (_remcells < 0) {
        /* back-track caused by error or completion of grid */
        nng_stack *st = _stack;
        
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
            
            if (~st->level & nng_BOTH) {
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
            return nng_LINE;
            /* finished loading from stack */
        } else {
            /* nothing left on stack - stop */
            return nng_FINISHED;
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
        return nng_UNFINISHED;
    } else if (_remcells == 0) {
        /* no remaining lines or cells; no error - must be solution */
        
        /// if (_client && _client->present) (*_client->present)(_client_data);
        _solutions_sum++;        
        _remcells = -1;
        return _stack ? nng_FOUND : nng_FINISHED;
    } else {
        /* no more info; no errors; some cells left
         - push stack to make a guess */
        nng_stack *st;
        size_t x, y, w, h;
        
        /* record the current state */
        /* create and insert new stack element */
        
        st = malloc(sizeof(nng_stack));
        st->next = _stack;
        _stack = st;
        st->remcells = _remcells;
        st->level = nng_BLANK;
        
        /* find area to be recorded */
#if nng_PUSHALL
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
        st->grid = malloc(w * h * sizeof(nng_cell));
        for (y = st->editarea.min.y; y < st->editarea.max.y; y++)
            memcpy(st->grid + (y - st->editarea.min.y) * w,
                   _grid + st->editarea.min.x + y * _puzzle->width, w);
        
        /* copy scores */
        st->rowattr = malloc(h * sizeof(nng_lineattr));
        st->colattr = malloc(w * sizeof(nng_lineattr));
        for (y = st->editarea.min.y; y < st->editarea.max.y; y++)
            st->rowattr[y - st->editarea.min.y] = _rowattr[y];
        for (x = st->editarea.min.x; x < st->editarea.max.x; x++)
            st->colattr[x - st->editarea.min.x] = _colattr[x];
        
        /* choose position to make guess */
        {
            int bestscore = -1000;
            for (x = st->editarea.min.x; x < st->editarea.max.x; x++)
                for (y = st->editarea.min.y; y < st->editarea.max.y; y++)
                    if (_grid[x + y * _puzzle->width] == nng_BLANK) {
                        int score = _rowattr[y].score + _colattr[x].score;
                        if (score < bestscore)
                            continue;
                        bestscore = score;
                        st->pos.x = x;
                        st->pos.y = y;
                    }
        }
        
        [self guess];
        return nng_LINE;
    }
    
    return nng_UNFINISHED;
}

-(void)focusRowLine:(int)lineno Value:(int)v { _focus = v;}
-(void)focusColLine:(int)lineno Value:(int)v { _focus = v;}
-(void)mark1Col:(int)lineno {}
-(void)mark1Row:(int)lineno {}
-(void)markFrom:(int)from To:(int)to {}

-(int)redeemStep {
    int changed = 0;
    nng_cell *line;
    nng_sizetype *rule;
    size_t linelen, rulelen, perplen;
    ptrdiff_t linestep, flagstep, rulestep;
    nng_lineattr *attr, *rattr, *cattr;
    nng_level *flag;
    
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
            case nng_BLANK:
                switch (_work[i]) {
                    case nng_DOT:
                    case nng_SOLID:
                        changed = 1;
                        if (!cells.inrange) {
                            cells.from = i;
                            cells.inrange = true;
                        }
                        line[i * linestep] = _work[i];
                        _remcells--;
                        
                        /* update score for perpendicular line */
                        attr = &rattr[i * flagstep];
                        if (!--*(_work[i] == nng_DOT ?
                                 &attr->dot : &attr->solid))
                            attr->score = perplen;
                        else
                            attr->score++;
                        
                        /* update score for solved line */
                        if (!--*(_work[i] == nng_DOT ? &cattr->dot : &cattr->solid))
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
    nng_stack *st = _stack;
    int guess;
    
    if (!st) return;
    
#if false
#if 0
    /* make guess */
    guess = st->level ? (nng_BOTH ^ st->level): _first;
#else
    /* hard-wired first choice */
#if 1
    /* dot first */
    guess = (st->level & nng_DOT) ? nng_SOLID : nng_DOT;
#else
    /* solid first */
    guess = (st->level & nng_SOLID) ? nng_DOT : nng_SOLID;
#endif
#endif
#else
    /* guess base on majority of unaccounted cells */
    guess = st->level ? (nng_BOTH ^ st->level) :
    (_rowattr[st->pos.y].dot + _colattr[st->pos.x].dot >
     _rowattr[st->pos.y].solid + _colattr[st->pos.x].solid ?
     nng_DOT : nng_SOLID);
#endif
    
    
    _grid[st->pos.x + st->pos.y * _puzzle->width] = guess;
    
    /* update score for row */
    if (!--*(guess == nng_DOT ?
             &_rowattr[st->pos.y].dot : &_rowattr[st->pos.y].solid))
        _rowattr[st->pos.y].score = _puzzle->height;
    else
        _rowattr[st->pos.y].score++;
    
    /* update score for column */
    if (!--*(guess == nng_DOT ?
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

-(void)findMinRect:(struct nng_rect *)b {
    int m = _puzzle->width * _puzzle->height;
    int first = 0, last = m - 1;
    size_t x, y;
    
    if (_puzzle->width == 0 || _puzzle->height == 0) {
        b->min.x = b->min.y = 0;
        b->max.x = _puzzle->width;
        b->max.y = _puzzle->height;
        return;
    }
    
    while (first < m && _grid[first] != nng_BLANK)
        first++;
    b->min.x = first % _puzzle->width;
    b->min.y = first / _puzzle->width;
    for (y = b->min.y + 1; y < _puzzle->height; y++) {
        for (x = 0; x < b->min.x &&
             _grid[x + y * _puzzle->width] != nng_BLANK; x++)
            ;
        b->min.x = x;
    }
    
    while (last >= first && _grid[last] != nng_BLANK)
        last--;
    b->max.x = last % _puzzle->width + 1;
    b->max.y = last / _puzzle->width + 1;
    for (y = b->max.y; y > b->min.y; ) {
        y--;
        for (x = _puzzle->width; x > b->max.x; ) {
            x--;
            if (_grid[x + y * _puzzle->width] == nng_BLANK) {
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
    struct nng_initargs a;
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
                case nng_DOT:
                case nng_SOLID:
                    _work[i] = a.line[i * a.linestep];
                    break;
                default:
                    _work[i] = nng_BOTH;
                    break;
            }
        
        _status = nng_DONE;
        return;
    }
    
    _status =
    (*_linesolver[_level - 1].suite->init)
    (_linesolver[_level - 1].context, &_workspace, &a) ?
    nng_WORKING : nng_DONE;
}

-(void)step {
    if (_level > _levels || _level < 1 ||
        !_linesolver[_level - 1].suite ||
        !_linesolver[_level - 1].suite->step) {
        size_t i, linelen = _on_row ? _puzzle->width : _puzzle->height;
        ptrdiff_t linestep = _on_row ? 1 : _puzzle->width;
        const nng_cell *line =
        _on_row ? _grid + _puzzle->width * _lineno : _grid + _lineno;
        
        /* reveal nothing */
        for (i = 0; i < linelen; i++)
            switch (line[i * linestep]) {
                case nng_DOT:
                case nng_SOLID:
                    _work[i] = line[i * linestep];
                    break;
                default:
                    _work[i] = nng_BOTH;
                    break;
            }
        
        _status = nng_DONE;
        return;
    }
    
    _status = (*_linesolver[_level - 1].suite->step)
    (_linesolver[_level - 1].context, _workspace.byte) ?
    nng_WORKING : nng_DONE;
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

/// fcomp


typedef enum {
    INVALID,
    SLIDING,
    DRAWING,
    RESTORING,
} stepmode;

#define CONTEXT(MR) \
struct { \
struct nng_initargs a; \
\
size_t remunk, block, base, max, mininv, target; \
stepmode mode; \
\
nng_sizetype pos[128], oldpos[128], solid[128], oldsolid[128], maxpos; \
}

#define RULE(I) (a->rule[(I) * a->rulestep])
#define POS(I) (ctxt->pos[I])
#define OLDPOS(I) (ctxt->oldpos[I])
#define SOLID(I) (ctxt->solid[I])
#define OLDSOLID(I) (ctxt->oldsolid[I])
#define B (ctxt->block)
#define LEN (a->linelen)
#define CELL(X) (a->line[(X) * a->linestep])
#define RESULT(X) (a->result[(X) * a->resultstep])
#define BASE (ctxt->base)
#define MAX (ctxt->max)
#define MININV (ctxt->mininv)
#define RULES (a->rulelen)

/* Return true if there are no cells remaining from which information
 could be obtained. */
static int record_section(const struct nng_initargs *a,
                          nng_sizetype from,
                          nng_sizetype to,
                          nng_cell v,
                          size_t *remunk)
{
    ++*a->fits;
    for (nng_sizetype i = from; i < to; i++) {
        assert(i < LEN);
        if (CELL(i) != nng_BLANK)
            continue;
        nng_cell *cp = &RESULT(i);
        if (*cp & v)
            continue;
        *cp |= v;
        assert(*cp < 4);
        if (*cp == nng_BOTH)
            if (--*remunk == 0)
                return true;
    }
    

    return false;
}

static int merge1(const struct nng_initargs *a,
                  nng_sizetype *pos,
                  nng_sizetype *oldpos,
                  nng_sizetype *solid,
                  nng_sizetype *oldsolid,
                  size_t *remunk,
                  size_t b)
{
    if (record_section(a, oldpos[b], pos[b], nng_DOT, remunk) ||
        record_section(a, oldpos[b] + RULE(b), pos[b] + RULE(b),
                       nng_SOLID, remunk))
        return true;
    
    oldpos[b] = pos[b];
    oldsolid[b] = solid[b];
    return false;
}

static int record_sections(const struct nng_initargs *a,
                           size_t base, size_t max,
                           nng_sizetype *pos,
                           nng_sizetype *oldpos,
                           nng_sizetype *solid,
                           nng_sizetype *oldsolid,
                           size_t *remunk)
{
    // Where does the section of dots before the first block start?
    nng_sizetype left = base > 0 ? pos[base - 1] + RULE(base - 1) : 0;
    
    for (size_t b = base; b < max; b++) {
        // Mark the dots leading up to the block.
        if (record_section(a, left, pos[b], nng_DOT, remunk))
            return true;
        
        // Where does this block end, and the next set of dots start?
        left = pos[b] + RULE(b);
        
        // Mark the solids of this block.
        if (record_section(a, pos[b], left, nng_SOLID, remunk))
            return true;
        
        oldpos[b] = pos[b];
        oldsolid[b] = solid[b];
    }
    
    // Mark the trailing dots.
    return record_section(a, left,
                          max == RULES ? LEN : pos[max],
                          nng_DOT, remunk);
}

void fcomp_prep(void *vp, const struct nng_lim *lim, struct nng_req *req)
{
    CONTEXT(lim->maxrule) ctxt;
    req->byte = sizeof ctxt;
}

int fcomp_init(void *vp, struct nng_ws *ws, const struct nng_initargs *a)
{
    
    *a->fits = 0;
    
    // Handle the special case of an empty rule.
    if (RULES == 0) {
        for (nng_sizetype i = 0; i < LEN; i++) {
            if (CELL(i) == nng_DOT)
                continue;
            if (CELL(i) != nng_BLANK)
                return false;
            RESULT(i) = nng_DOT;
        }
        *a->fits = 1;
        return false;
    }
    
    CONTEXT(RULES) *ctxt = ws->byte;
    ctxt->a = *a;
    
    
    // The left-most block that hasn't been fixed yet is 0.
    BASE = 0;
    
    // No blocks on the right have fixed either.
    MAX = RULES;
    ctxt->maxpos = LEN;
    
    // Record how many cells are left that have not yet been determined
    // to be 'BOTH'.
    ctxt->remunk = 0;
    for (nng_sizetype i = 0; i < LEN; i++) {
        if (CELL(i) == nng_BLANK) {
            ctxt->remunk++;
            RESULT(i) = nng_BLANK;
        } else
            RESULT(i) = CELL(i);
        

    }

    // No blocks are valid to start with, and their minimum positions
    // are all zero.
    ctxt->mode = INVALID;
    B = 0;
    MININV = 0;
    for (size_t b = 0; b < RULES; b++) {
        POS(b) = OLDPOS(b) = 0;
        SOLID(b) = OLDSOLID(b) = LEN + 1;
    }
    
    // We assume that there is more work to do.
    return true;
}

// Look for a gap of length 'req', starting at '*at', going no further
// than 'lim'.  Return true, and write the position in '*at'.
static int can_jump(const struct nng_initargs *a,
                    nng_sizetype req,
                    nng_sizetype lim,
                    nng_sizetype *at)
{
    nng_sizetype got = 0;
    for (nng_sizetype i = *at; i < lim && got < req; i++) {
        if (CELL(i) == nng_DOT) {
            got = 0;
            *at = i + 1;
        } else {
            // We can be sure that there are no solids between us and the
            // next block/end of line.
            assert(CELL(i) == nng_BLANK);
            got++;
        }
    }
    
    return got >= req;
}

static int step_invalid(void *vp, void *ws);
static int step_drawing(void *vp, void *ws);
static int step_sliding(void *vp, void *ws);
static int step_restoring(void *vp, void *ws);

static int fcomp_step(void *vp, void *ws)
{
    const struct nng_initargs *a = ws;
    CONTEXT(RULES) *ctxt = ws;
    
    switch (ctxt->mode) {
        case DRAWING:
            return step_drawing(vp, ws);
        case SLIDING:
            return step_sliding(vp, ws);
        case INVALID:
            return step_invalid(vp, ws);
        case RESTORING:
            return step_restoring(vp, ws);
        default:
            assert(!"Invalid state");
    }
    
    return false;
}

static int step_invalid(void *vp, void *ws)
{
    const struct nng_initargs *a = ws;
    CONTEXT(RULES) *ctxt = ws;
    
    if (B >= MAX) {
        // All blocks are in place.
        
        if (B <= BASE) {
            // That must be the lot.
            return false;
        }
        
        // Go back to the previous block for some checks.
        B--;
        
        // Check for trailing solids before the next block or the end of
        // the line.
        for (nng_sizetype i = POS(B) + RULE(B); i < ctxt->maxpos; i++)
            if (CELL(i) == nng_SOLID) {
                // A trailing solid has been found.
                
                // Can we jump to it without uncovering a solid?
                if (POS(B) + SOLID(B) + RULE(B) > i) {
                    // Yes, so do so, and revalidate.
                    POS(B) = i + 1 - RULE(B);
                    ctxt->mode = INVALID;
                    return true;
                }
                // No, we'd uncover a solid.
                
                // Try to bring up an earlier block.
                assert(SOLID(B) < RULE(B));
                ctxt->target = B;
                ctxt->mode = DRAWING;
                return true;
            }
        // All blocks in position, and no trailing solids found - all valid.
        
        // Record the current state in the results.
        if (record_sections(a, MININV, MAX,
                            ctxt->pos, ctxt->oldpos,
                            ctxt->solid, ctxt->oldsolid,
                            &ctxt->remunk))
            return false;
        MININV = MAX;
        
        // Start sliding the right-most unfixed block right.
        ctxt->mode = SLIDING;
        return true;
    }
    
    if (POS(B) + RULE(B) > ctxt->maxpos) {
        // This block has spilled over the end of the line or onto a
        // right-most fixed block.
        
        // Restore everything back to where we diverged from a valid
        // state.
        ctxt->mode = RESTORING;
        return true;
    }
    
    // Determine whether this block covers any solids or dots.
    nng_sizetype i = POS(B), end = i + RULE(B);
    SOLID(B) = LEN + 1;
    while (i < end && CELL(i) != nng_DOT) {
        if (SOLID(B) >= RULE(B) && CELL(i) == nng_SOLID)
            SOLID(B) = i - POS(B);
        i++;
    }
    
    if (i < end) {
        // There is a dot under this block.
        
        if (SOLID(B) < RULE(B)) {
            // But there's a solid before it, so we can't jump.
            
            // Bring up another block.
            ctxt->target = B;
            ctxt->mode = DRAWING;
            return true;
        }
        
        // Otherwise, skip the dot, and recompute the solid offset.
        POS(B) = i + 1;
        ctxt->mode = INVALID;
        return true;
    }
    
    // If the block is not covering a solid, but just touching one on
    // its right, pretend that the block overlaps it.
    if (SOLID(B) >= RULE(B) && end < LEN && CELL(end) == nng_SOLID)
        SOLID(B) = RULE(B);
    
    // Keep moving the block one cell at a time, in order to cover any
    // adjacent solid on its right.
    while (POS(B) + RULE(B) < ctxt->maxpos &&
           CELL(POS(B) + RULE(B)) == nng_SOLID) {
        if (SOLID(B) == 0) {
            // We can't span both the solid we cover and the adjacent solid
            // at the end.
            
            // Bring up another block.
            ctxt->target = B;
            ctxt->mode = DRAWING;
            return true;
        }
        POS(B)++;
        SOLID(B)--;
    }
    // This block is in a valid position.

    if (SOLID(B) < RULE(B))
    // Position the next block and try to validate it.
    if (B + 1 < MAX && POS(B + 1) < POS(B) + RULE(B) + 1)
        POS(B + 1) = POS(B) + RULE(B) + 1;
    B++;
    ctxt->mode = INVALID;
    return true;
}

static int step_drawing(void *vp, void *ws)
{
    const struct nng_initargs *a = ws;
    CONTEXT(RULES) *ctxt = ws;
    
    assert(SOLID(ctxt->target) < RULE(ctxt->target));
    
    do {
        if (B <= BASE)
            // There are no more solids.  We must have exhausted all
            // possibilities, so stop here.
            return false;
        
        if (MININV < MAX) {
            // mininv has been set
            
            assert(B >= MININV);
            if (B == MININV) {
                assert(MAX > 0);
                B = MAX - 1;
                ctxt->mode = RESTORING;
                return true;
            }
        }
        
        if (SOLID(B) < RULE(B))
            ctxt->target = B;
        B--;
    } while (SOLID(B) < RULE(B) &&
             POS(ctxt->target) + SOLID(ctxt->target) - RULE(B) + 1 >
             POS(B) + SOLID(B));
    
    // We must record which left-most block we are about to disturb from
    // its last valid position.
    if (B < MININV)
        MININV = B;
    
    // Set the block near to the position of the next block, so that
    // it just overlaps the solid, and try again.
    POS(B) = POS(ctxt->target) + SOLID(ctxt->target) - RULE(B) + 1;
    
    // This block should still have a position completely on the line,
    // since the solid we aimed to cover must be on the line.
    assert(POS(B) + RULE(B) <= LEN);
    
    // Start checking whether this and later blocks are valid.
    ctxt->mode = INVALID;
    
    // Try again.
    return true;
}

static int step_sliding(void *vp, void *ws)
{
    const struct nng_initargs *a = ws;
    CONTEXT(RULES) *ctxt = ws;
    
    // Attempt to slide this block to the right.
    
    // How far to the right can we shift it before it hits the next
    // block or the end of the line?
    nng_sizetype lim = B + 1 < RULES ? POS(B + 1) - 1 : LEN;
    
    assert(POS(B) == OLDPOS(B));
    assert(SOLID(B) == OLDSOLID(B));
    
    // Slide right until we reach the next block, the end of the line,
    // or a dot.  Also stop if we are about to uncover a solid.
    while (POS(B) + RULE(B) < lim &&
           CELL(POS(B) + RULE(B)) != nng_DOT &&
           SOLID(B) != 0) {
        // We shouldn't be about to cover a solid by moving.  Otherwise,
        // how could we be in a valid state?
        assert(CELL(POS(B) + RULE(B)) != nng_SOLID);
        
        // Keep track of the left-most solid that we are covering, as we
        // move right one cell.
        if (SOLID(B) > 0)
            SOLID(B)--;
        else
            SOLID(B) = LEN + 1;
        POS(B)++;
    }
    
    assert(POS(B) >= OLDPOS(B));
    
    if (POS(B) != OLDPOS(B)) {
        // We have managed to slide this block some distance, so record
        // all those possibilities, and try later.  However, if this rules
        // out further information from this line, stop.

        if (merge1(a, ctxt->pos, ctxt->oldpos,
                   ctxt->solid, ctxt->oldsolid, &ctxt->remunk, B))
            return false;
    }
    
    // We failed to slide the block beyond this point.  Why?
    
    if (POS(B) + RULE(B) == lim && B + 1 == MAX) {
        // This block is at its right-most position.
        if (MAX == BASE) {
            return false;
        }
        MAX--;
        ctxt->maxpos = POS(B) - 1;
    } else if (POS(B) + RULE(B) < lim &&
               CELL(POS(B) + RULE(B)) == nng_DOT) {
        // There's a dot in the way.
        
        // Can we jump it?
        nng_sizetype at = POS(B) + RULE(B) + 1;
        if (POS(B) + RULE(B) * 2 < lim && can_jump(a, RULE(B), lim, &at)) {
            // There is space to jump over the dot.
            
            assert(OLDPOS(B) == POS(B));
            
            if (SOLID(B) >= RULE(B)) {
                // And we're not covering a solid, so we can do it now, and
                // keep sliding.
                
                // Jump to the space.
                POS(B) = at;
                
                // Record the previous section as dots.
                if (record_section(a, OLDPOS(B), OLDPOS(B) + RULE(B),
                                   nng_DOT, &ctxt->remunk))
                    return false;
                
                // Record the new section as solids.
                if (record_section(a, POS(B), POS(B) + RULE(B),
                                   nng_SOLID, &ctxt->remunk))
                    return false;
                
                // Note that this move has been recorded.
                OLDPOS(B) = POS(B);
                OLDSOLID(B) = SOLID(B) = LEN + 1;
                
                // Keep sliding this block.
                ctxt->mode = SLIDING;
                return true;
            }
            // There's space to jump the dot, but we'd uncover a solid if we
            // did that.
        } else {
            // There's no space to jump over the dot.
            
            if (B + 1 == MAX) {
                // This block is at its right-most position.
                if (MAX == BASE) {
                    return false;
                }
                MAX--;
                ctxt->maxpos = POS(B) - 1;
            }
        }
        // Finished handling an obstructive dot.
    }
    // Either there was no dot, or we failed to jump over it.
    
    // We can't go any further for the moment.  Try sliding a previous
    // block.
    if (B > BASE) {
        B--;
        return true;
    }
    // This is the left-most block that hasn't been fixed.
    
    // Now go to the right-most block that hasn't been fixed, and try to
    // get an earlier block to cover it.
    if (MAX <= BASE) {
        // All blocks have been fixed from the right.  Stop here.
        return false;
    }
    
    assert(MAX > 0);
    B = MAX - 1;
    
    // Skip blocks which don't cover solids.
    while (B > BASE && SOLID(B) >= RULE(B))
        B--;
    
    if (SOLID(B) >= RULE(B)) {
        // We ran out of blocks, so it must be the end.
        return false;
    }
    
    // Pull a block up to cover this one's solid.
    ctxt->target = B;
    ctxt->mode = DRAWING;
    return true;
}

static int step_restoring(void *vp, void *ws)
{
    const struct nng_initargs *a = ws;
    CONTEXT(RULES) *ctxt = ws;
    
    assert(B < RULES);
    assert(B < MAX);
    
    // Restore all blocks to their last valid positions, and find the
    // left-most of them that covers a solid - this will be the target
    // for drawing the next block up.
    ctxt->target = RULES;
    for (size_t j = MININV; j <= B; j++) {
        size_t i = B + MININV - j;

        POS(i) = OLDPOS(i);
        SOLID(i) = OLDSOLID(i);
        if (SOLID(i) < RULE(i))
            ctxt->target = i;
    }
    
    
    B = MININV;
    MININV = RULES;
    if (B > MAX)
        B = MAX;
    
    if (ctxt->target >= RULES) {
        // Find a block from this position that covers a solid.
        while (B > BASE && SOLID(B) >= RULE(B))
            B--;
        
        if (SOLID(B) >= RULE(B)) {
            // There's no such block.
            return false;
        }
        ctxt->target = B;
    }
    
    // Now try drawing up an earlier block.
    ctxt->mode = DRAWING;
    return true;
}

