
/* make puzzle */
static int make_puzzle(nonogram_puzzle *p)
{

  return 0;
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


int main()
{
  // set the puzzle
  nonogram_puzzle p;

  // set the result grid
  nonogram_grid g;

  //1. verify the puzzle 

  // 2. 
  nonogram_initsolver(&handle.solver);
  nonogram_setalgo(&handle.solver, c->algo);
  nonogram_setlog(&handle.solver, handle.logfp, 0, c->loglevel);
  nonogram_setclient(&handle.solver, &our_client, &handle);

  /* now load the puzzle after configuration */
  nonogram_load(&handle.solver, &handle.puzzle, handle.grid,
                nonogram_puzzlewidth(&handle.puzzle) *
                nonogram_puzzleheight(&handle.puzzle));

  handle.stop = false;
  while (!handle.stop &&
	 nonogram_runsolver_n(&handle.solver,
			      (tries = 1, &tries)) != nonogram_FINISHED)
    ;

  nonogram_termsolver(&handle.solver);
  nonogram_freegrid(handle.grid);



  return 0;
}
