// P0-02-R2 commit-event fixture driver.
#include "Vretire_event_fixture.h"
#include "verilated.h"

#include <cstdio>
#include <cstdlib>

struct Tb {
  Vretire_event_fixture* dut;
  int errors = 0;
  explicit Tb(Vretire_event_fixture* d) : dut(d) {}
  void check(bool c, const char* m) {
    if (!c) { std::fprintf(stderr, "P0-02_EVENT_FAIL: %s\n", m); ++errors; }
  }
  void tick() { dut->clk=0; dut->eval(); dut->clk=1; dut->eval(); dut->clk=0; dut->eval(); }
  void reset() {
    dut->reset=1; dut->slot_valid=0; dut->s1_exc_valid=0;
    dut->s1_exc_cause=0; dut->s1_exc_tval=0; dut->s1_pc=0;
    tick(); dut->reset=0; tick();
  }
};

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Vretire_event_fixture* d = new Vretire_event_fixture;
  Tb tb(d);
  tb.reset();

  // Two normal slots.
  d->slot_valid = 3;
  d->s1_exc_valid = 0;
  tb.tick();
  tb.check(d->retire_valid == 3, "two normal slots did not retire");
  tb.check(!d->trap_valid, "unexpected trap");

  // S0 normal + S1 exception: S0 retires now, Trap next cycle.
  tb.reset();
  d->slot_valid = 3;
  d->s1_exc_valid = 1;
  d->s1_exc_cause = 2;
  d->s1_exc_tval = 0xdeadbeef;
  d->s1_pc = 0x80000008;
  tb.tick();
  tb.check(d->retire_valid == 1, "S0 did not retire before deferred Trap");
  tb.check(!d->trap_valid, "Trap emitted in the same cycle as retirement");
  d->slot_valid = 0;
  d->s1_exc_valid = 0;
  tb.tick();
  tb.check(d->retire_valid == 0, "normal retire during Trap cycle");
  tb.check(d->trap_valid == 1, "deferred Trap missing");
  tb.check(d->trap_cause == 2, "Trap cause lost");
  tb.check(d->trap_tval == 0xdeadbeef, "Trap tval lost");
  tb.check(d->trap_pc == 0x80000008, "Trap PC lost");
  tb.tick();
  tb.check(d->trap_valid == 0, "Trap repeated");

  // Non-contiguous input cannot retire S1 alone.
  tb.reset();
  d->slot_valid = 2;
  tb.tick();
  tb.check(d->retire_valid == 0, "retired S1 without S0");

  d->final();
  delete d;
  if (tb.errors == 0) {
    std::printf("P0-02_RETIRE_EVENT_FIXTURE_PASS\n");
    return 0;
  }
  std::fprintf(stderr, "P0-02_RETIRE_EVENT_FIXTURE_FAIL errors=%d\n", tb.errors);
  return 1;
}
