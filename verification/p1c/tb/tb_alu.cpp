// P1-C ALU unit reference test. Expected values are computed independently in
// C++ from RV32I semantics, not from a copied DUT case table.
#include "Valu_tb_top.h"
#include "verilated.h"
#include <cstdint>
#include <cstdio>
#include <random>

static int errors = 0;
static const uint32_t EDGE[] = {0u, 1u, 2u, 31u, 32u, 0xffffffffu,
                                0x80000000u, 0x7fffffffu, 0x55555555u,
                                0xaaaaaaaau};

static void check(bool c, const char* what, uint32_t got, uint32_t want) {
  if (!c) {
    std::fprintf(stderr, "P1C_ALU_FAIL: %s got=0x%08x want=0x%08x\n",
                 what, got, want);
    ++errors;
  }
}

static int32_t s32(uint32_t x) { return static_cast<int32_t>(x); }

struct Ref { uint32_t result, target; bool taken, control; };

static Ref ref_alu(uint32_t op, uint32_t a, uint32_t b,
                   uint32_t pc, uint32_t imm) {
  Ref r{0, 0, false, false};
  switch (op) {
    case 0: r.result = a + b; break;
    case 1: r.result = a - b; break;
    case 2: r.result = a << (b & 31); break;
    case 3: r.result = (s32(a) < s32(b)) ? 1 : 0; break;
    case 4: r.result = (a < b) ? 1 : 0; break;
    case 5: r.result = a ^ b; break;
    case 6: r.result = a >> (b & 31); break;
    case 7: r.result = static_cast<uint32_t>(s32(a) >> (b & 31)); break;
    case 8: r.result = a | b; break;
    case 9: r.result = a & b; break;
    case 10: r.result = a + imm; break;
    case 11: r.result = (s32(a) < s32(imm)) ? 1 : 0; break;
    case 12: r.result = (a < imm) ? 1 : 0; break;
    case 13: r.result = a ^ imm; break;
    case 14: r.result = a | imm; break;
    case 15: r.result = a & imm; break;
    case 16: r.result = a << (imm & 31); break;
    case 17: r.result = a >> (imm & 31); break;
    case 18: r.result = static_cast<uint32_t>(s32(a) >> (imm & 31)); break;
    case 19: r.result = imm; break;
    case 20: r.result = pc + imm; break;
    case 21: r.result = pc + 4; r.target = pc + imm; r.control = true; break;
    case 22: r.result = pc + 4; r.target = (a + imm) & ~1u; r.control = true; break;
    case 23: r.target = pc + imm; r.taken = (a == b); r.control = true; break;
    case 24: r.target = pc + imm; r.taken = (a != b); r.control = true; break;
    case 25: r.target = pc + imm; r.taken = (s32(a) < s32(b)); r.control = true; break;
    case 26: r.target = pc + imm; r.taken = (s32(a) >= s32(b)); r.control = true; break;
    case 27: r.target = pc + imm; r.taken = (a < b); r.control = true; break;
    case 28: r.target = pc + imm; r.taken = (a >= b); r.control = true; break;
    default: break;
  }
  return r;
}

static void run(Valu_tb_top* d, uint32_t op, uint32_t a, uint32_t b,
                uint32_t pc, uint32_t imm) {
  d->op = op; d->a = a; d->b = b; d->pc = pc; d->imm = imm; d->eval();
  Ref r = ref_alu(op, a, b, pc, imm);
  check(d->result == r.result, "result", d->result, r.result);
  check(d->target == r.target, "target", d->target, r.target);
  check(d->branch_taken == r.taken, "branch_taken", d->branch_taken, r.taken);
  check(d->is_control == r.control, "is_control", d->is_control, r.control);
}

static uint32_t sext12(uint32_t v) {
  v &= 0xfffu;
  return (v & 0x800u) ? (v | 0xfffff000u) : v;
}

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Valu_tb_top* d = new Valu_tb_top;
  const uint32_t base = 0x80000123u;

  // Explicit imm12 sign-extension and high-imm anchors.
  const int32_t anchors[4] = {-2048, -1, 0, 2047};
  for (uint32_t op = 10; op <= 15; ++op)
    for (int32_t av : anchors)
      run(d, op, 0x80000001u, 0, base, static_cast<uint32_t>(av));
  run(d, 16, 0x80000001u, 0, base, 0);
  run(d, 16, 0x80000001u, 0, base, 31);
  run(d, 16, 0x80000001u, 0, base, 63);
  run(d, 17, 0x80000001u, 0, base, 31);
  run(d, 18, 0x80000001u, 0, base, 31);
  run(d, 19, 0, 0, base, 0x80000000u);
  run(d, 19, 0, 0, base, 0xfffff000u);
  run(d, 19, 0, 0, base, 0x7ffff000u);
  run(d, 20, 0, 0, 0x80000000u, 0x00001000u);
  run(d, 20, 0, 0, 0xfffff000u, 0x00001000u);

  for (uint32_t op = 0; op <= 28; ++op) {
    for (uint32_t a : EDGE) {
      for (uint32_t b : EDGE) {
        uint32_t imm = (op <= 18) ? sext12(b) : (b & 0x1fffu);
        run(d, op, a, b, base, imm);
      }
    }
  }
  std::mt19937 rng(0x5eedc0deu);
  for (int i = 0; i < 20000; ++i) {
    uint32_t op = rng() % 29;
    uint32_t a = rng(), b = rng();
    uint32_t imm;
    if (op <= 15) imm = sext12(rng());
    else if (op <= 18) imm = rng() & 0x3fu;
    else if (op == 19 || op == 20) imm = rng() & 0xfffff000u;
    else imm = rng() & 0x1fffeu;
    run(d, op, a, b, rng(), imm);
    if (errors > 20) break;
  }
  delete d;
  if (errors) { std::printf("P1C_ALU_FAIL errors=%d\n", errors); return 1; }
  std::printf("P1C_ALU_PASS ops=29 directed=%zu random=20000\n",
              sizeof(EDGE)/sizeof(EDGE[0]) * sizeof(EDGE)/sizeof(EDGE[0]) * 29);
  return 0;
}
