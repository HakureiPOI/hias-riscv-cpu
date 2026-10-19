/* P0-01 freestanding self-checking program.
 *
 * Expected values are fixed and independent of the host:
 *   helper(10) = sum(i*3 + 1, i = 0..9) = 145
 *   mix(3)     = 178
 *
 * The program uses .text, .rodata, .data, .bss and the stack so the smoke
 * test exercises more than a single code path. It never calls libc.
 *
 * Build variants:
 *   default      -> success path, exit code 0
 *   SMOKE_FAIL=1 -> inverted check, exit code 1 (negative control)
 *   SMOKE_HANG=1 -> infinite loop, no tohost write (timeout control)
 */

#define SMOKE_PASS_SIGNATURE 0x50415353u /* "PASS" */
#define SMOKE_FAIL_SIGNATURE 0x4641494cu /* "FAIL" */

volatile unsigned int smoke_signature;
volatile unsigned int smoke_counter = 3;

static const unsigned int weights[4] = {2u, 3u, 5u, 7u};

__attribute__((noinline)) static int helper(int n) {
    volatile int acc = 0;
    int i;
    for (i = 0; i < n; i++) {
        acc += i * 3 + 1;
    }
    return acc;
}

__attribute__((noinline)) static unsigned int mix(unsigned int x) {
    unsigned int y = x;
    int i;
    for (i = 0; i < 4; i++) {
        y = (y ^ weights[i]) + (y << 1);
    }
    return y;
}

int main(void) {
#if defined(SMOKE_HANG) && SMOKE_HANG
    for (;;) {
        __asm__ volatile("nop");
    }
#else
    int sum = helper(10);
    unsigned int mixed = mix(smoke_counter);
    int ok = (sum == 145) && (mixed == 178u);

#if defined(SMOKE_FAIL) && SMOKE_FAIL
    ok = !ok;
#endif

    if (ok) {
        smoke_signature = SMOKE_PASS_SIGNATURE;
        return 0;
    }
    smoke_signature = SMOKE_FAIL_SIGNATURE;
    return 1;
#endif
}
