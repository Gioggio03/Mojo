/* Set of functions in C used by MoStream at low level */

#include<pthread.h>
#include<sched.h>
#include<stdint.h>
#include<errno.h>

// Pins the current thread to the specified CPU core. Returns 0 on success, or a non-zero errno on failure
int pin_thread_to_cpu(int cpu)
{
    cpu_set_t cpuset;
    CPU_ZERO(&cpuset);
    CPU_SET(cpu, &cpuset);

    int err = pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset);
    if (err != 0)
        return err; // non-zero errno on failure
    return 0;
}

// Pins the current thread to the specified CPU core. Returns 0 on success, or a negative errno on failure
int pin_thread_to_cpu_checked(int cpu)
{
    int r = pin_thread_to_cpu(cpu);
    if (r == 0)
        return 0;
    return -r;
}
