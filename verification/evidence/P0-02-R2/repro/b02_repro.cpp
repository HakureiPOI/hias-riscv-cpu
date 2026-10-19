#include "Vinterface_fixture.h"
#include "verilated.h"
#include <cstdio>

static Vinterface_fixture* d;
static void tick(){ d->clk=0; d->eval(); d->clk=1; d->eval(); d->clk=0; d->eval(); }
static void reset(){ d->reset=1; d->flush=0; d->in_valid=0; d->resources=2; d->alloc_req=0; d->resp_valid=0; tick(); d->reset=0; tick(); }
static void alloc(){ d->alloc_req=1; d->clk=0; d->eval(); tick(); d->alloc_req=0; }
static void flush(){ d->flush=1; tick(); d->flush=0; tick(); }
static int alloc_ready(){ d->clk=0; d->eval(); return d->alloc_ready; }
static int alloc_idx(){ d->clk=0; d->eval(); return d->alloc_idx; }
static int alloc_gen(){ d->clk=0; d->eval(); return d->alloc_gen; }
static int resp_accept(int idx,int gen){ d->resp_valid=1; d->resp_idx=idx; d->resp_gen=gen; d->clk=0; d->eval(); int a=d->resp_accept; tick(); d->resp_valid=0; return a; }

int main(int argc,char**argv){
  Verilated::commandArgs(argc,argv); d=new Vinterface_fixture;
  // R1: allocation -> flush -> reallocation -> old response
  reset(); d->alloc_req=1; d->clk=0; d->eval();
  int a_idx=d->alloc_idx, a_gen=d->alloc_gen, a_ready=d->alloc_ready; tick(); d->alloc_req=0;
  printf("B02_R1_first_alloc ready=%d idx=%d gen=%d\n",a_ready,a_idx,a_gen);
  flush();
  d->alloc_req=1; d->clk=0; d->eval();
  int b_idx=d->alloc_idx,b_gen=d->alloc_gen,b_ready=d->alloc_ready; tick(); d->alloc_req=0;
  printf("B02_R1_after_flush_alloc ready=%d idx=%d gen=%d\n",b_ready,b_idx,b_gen);
  printf("B02_R1_old_response_accepted=%d\n", resp_accept(a_idx,a_gen));

  // R2: same-cycle allocation and completion must preserve active count
  reset();
  for(int i=0;i<2;i++){ d->alloc_req=1; d->clk=0; d->eval(); tick(); d->alloc_req=0; }
  // active {0,1}, next=2. Two cycles with one alloc + one free each.
  for(int i=0;i<2;i++){
    d->alloc_req=1; d->resp_valid=1; d->resp_idx=i; d->resp_gen=0;
    d->clk=0; d->eval(); tick(); d->alloc_req=0; d->resp_valid=0;
  }
  // Two more allocations; with correct accounting active count reaches 4.
  for(int i=0;i<2;i++){ d->alloc_req=1; d->clk=0; d->eval(); tick(); d->alloc_req=0; }
  d->alloc_req=1; d->clk=0; d->eval();
  printf("B02_R2_after_4_active alloc_ready=%d alloc_idx=%d\n",d->alloc_ready,d->alloc_idx);
  d->alloc_req=0;

  // R3: non-head completion then allocation must not overwrite active target
  reset();
  for(int i=0;i<4;i++){ d->alloc_req=1; d->clk=0; d->eval(); tick(); d->alloc_req=0; }
  resp_accept(1,0);  // free non-head
  d->alloc_req=1; d->clk=0; d->eval();
  printf("B02_R3_after_nonhead_free alloc_ready=%d alloc_idx=%d\n",d->alloc_ready,d->alloc_idx);
  d->alloc_req=0;

  delete d; return 0;
}
