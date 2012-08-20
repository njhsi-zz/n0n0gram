#include "nonogram.h"



/* picture file format: line break is must.  */
static int make_puzzle_by_p(const char* inf, nonogram_puzzle *p)
{

  p->width = p->height = 0;

  FILE *fin = fopen(inf, "r");

  const char S='#', D='-';

  size_t w=0, h=0;

  nonogram_cell *g = loadgrid(&w, &h, fin, S, D);

  nonogram_makepuzzle(p,g,w,h);

}

/*verify puzzle*/
int verify_puzzle(const nonogram_puzzle *p)
{
  int sum = 0;
  size_t lineno, relno;

  for (lineno = 0; lineno < p->height; lineno++)
    for (relno = 0; relno < p->row[lineno].len; relno++)
      sum += p->row[lineno].val[relno];

  for (lineno = 0; lineno < p->width; lineno++)
    for (relno = 0; relno < p->col[lineno].len; relno++)
      sum -= p->col[lineno].val[relno];

  return sum;
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
        printf("\n");
    count++;
  }

    printf("\n");
  return count;
}


int main()
{
  // set the puzzle
  nonogram_puzzle p;


  //  make_puzzle(&p);
  make_puzzle_by_p("pic.txt",&p);

  // set the result grid
  nonogram_cell* g = (nonogram_cell*)malloc(p.width*p.height*sizeof(nonogram_cell)) ;

  nonogram_solver c;

  //1. verify the puzzle 
  int i = verify_puzzle(&p);
  printf("verify:%d. w=%d, h=%d \n",i, nonogram_puzzlewidth(&p),nonogram_puzzleheight(&p));

  // 2. 
  nonogram_initsolver(&c);

  /* now load the puzzle after configuration */
  nonogram_load(&c, &p, g,
                nonogram_puzzlewidth(&p) *
                nonogram_puzzleheight(&p));

  int bstop = false;
  int tries;
  while (!bstop &&
	 nonogram_runsolver_n(&c,
			      (tries = 1, &tries)) != nonogram_FINISHED)
    ;

    nonogram_termsolver(&c);

    printgrid(c.grid,p.width,p.height,"#","-"," ");

  //  nonogram_freegrid(g);



  return 0;
}
