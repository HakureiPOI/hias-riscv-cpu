#include "Vram_bridge_tb_top.h"
#include "verilated.h"
#include <cstdint>
#include <cstdio>
#include <cstring>

struct Req { bool store; uint64_t pa; uint8_t size; uint8_t mask; uint32_t wdata; };
static Vram_bridge_tb_top* d;

static void tick(){ d->clk=0; d->eval(); d->clk=1; d->eval(); d->clk=0; d->eval(); }
static void reset(){ d->reset=1; d->load_valid=0; d->flush_i=0; d->resp_delay_i=0; d->req_valid=0; d->resp_ready=0; tick(); d->reset=0; tick(); }
static void load_word(uint16_t word, uint32_t data){ d->load_valid=1; d->load_word_addr=word; d->load_data=data; tick(); d->load_valid=0; tick(); }
static void transact(Req r, const char* name){
  d->req_valid=1; d->req_is_store=r.store; d->req_va=(uint32_t)r.pa; d->req_pa=r.pa;
  d->req_size=r.size; d->req_byte_mask=r.mask; d->req_wdata=r.wdata; d->req_cacheable=1; d->req_priv=3;
  d->req_id=7; d->req_gen=9; d->resp_ready=1;
  bool accepted=false, done=false; bool err=false, valid=false; uint32_t rdata=0; uint8_t cause=0;
  for(int i=0;i<100 && !done;i++){
    d->clk=0; d->eval();
    bool acc = d->req_valid && d->req_ready;
    bool rv = d->resp_valid;
    if(rv){ valid=true; err=d->resp_error; cause=d->resp_cause; rdata=d->resp_rdata; }
    d->clk=1; d->eval();
    if(acc){ accepted=true; d->req_valid=0; }
    if(rv && d->resp_ready) done=true;
    d->clk=0; d->eval();
  }
  printf("%s accepted=%d resp_valid=%d error=%d cause=%u rdata=0x%08x\n",
         name, accepted, valid, err, cause, rdata);
}
int main(int argc,char**argv){
  Verilated::commandArgs(argc,argv); d=new Vram_bridge_tb_top;
  reset();
  load_word(32766, 0x11223344u); // guard word
  load_word(32767, 0xA1B2C3D4u); // tail word
  printf("tail_initial=0x%08x guard_initial=0x%08x\n", 0xA1B2C3D4u, 0x11223344u);
  transact({false,0x3ffffffffull,0,0x8,0}, "TOP_BYTE_READ");
  transact({false,0x3fffffffeull,1,0xC,0}, "TOP_HALF_READ");
  transact({false,0x3fffffffcull,2,0xF,0}, "TOP_WORD_READ");
  transact({false,0x80000000ull,3,0xF,0}, "SIZE3_READ");
  transact({true,0x3ffffffffull,0,0x8,0x5A}, "TOP_BYTE_WRITE");
  transact({false,0x8001fffcull,2,0xF,0}, "TAIL_READ_AFTER_BYTE");
  transact({true,0x3fffffffcull,2,0xF,0xDEADBEEF}, "TOP_WORD_WRITE");
  transact({false,0x8001fffcull,2,0xF,0}, "TAIL_READ_AFTER_WORD");
  transact({false,0x8001fff8ull,2,0xF,0}, "GUARD_READ_AFTER_WORD");
  delete d; return 0;
}
