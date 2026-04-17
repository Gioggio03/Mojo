#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <chrono>
#include <cstdio>
#include <algorithm>
#include <thread>
#include <atomic>
#include <vector>

const int W=512, H=512, PLANE=W*H;
const int ITERS=10000;
const int WORKERS=5;

static void sharpen_v4(const uint8_t* __restrict__ src, uint8_t* __restrict__ dst) {
    for (int ch=0;ch<3;ch++) {
        const uint8_t* s=src+ch*PLANE; uint8_t* d=dst+ch*PLANE;
        for(int y=1;y<H-1;y++){
            const uint8_t*rm=s+(y-1)*W,*r0=s+y*W,*rp=s+(y+1)*W;
            uint8_t*out=d+y*W;
            for(int x=1;x<W-1;x++){
                int16_t v=(int16_t)r0[x]*5-rm[x]-rp[x]-r0[x-1]-r0[x+1];
                out[x]=(uint8_t)std::clamp((int16_t)v,(int16_t)0,(int16_t)255);
            }
        }
    }
}

static void sharpen_v2(const uint8_t* __restrict__ in, uint8_t* __restrict__ out) {
    for(int y=1;y<H-1;y++){
        for(int x=1;x<W-1;x++){
            int c=(y*W+x)*3,up=((y-1)*W+x)*3,dn=((y+1)*W+x)*3,lt=(y*W+x-1)*3,rt=(y*W+x+1)*3;
            for(int ch=0;ch<3;ch++){
                int v=in[c+ch]*5-in[up+ch]-in[dn+ch]-in[lt+ch]-in[rt+ch];
                out[c+ch]=(uint8_t)std::clamp(v,0,255);
            }
        }
    }
}

// Simulate WORKERS parallel workers, each doing alloc+compute+free
void run_parallel(const char* name, bool is_v4, int nworkers) {
    std::atomic<long long> total_ns{0};
    std::vector<std::thread> threads;

    auto worker_fn = [&](int) {
        long long ns = 0;
        for(int i=0;i<ITERS/nworkers;i++) {
            // Simulate incoming image (from previous stage)
            auto* in = new uint8_t[PLANE*3]();
            memset(in, 128, PLANE*3);

            auto t0 = std::chrono::high_resolution_clock::now();
            auto* out = new uint8_t[PLANE*3]();
            if(is_v4) sharpen_v4(in, out);
            else      sharpen_v2(in, out);
            delete[] in;  // like svc() deletes input
            ns += std::chrono::duration_cast<std::chrono::nanoseconds>(
                std::chrono::high_resolution_clock::now()-t0).count();

            delete[] out;
        }
        total_ns += ns;
    };

    for(int w=0;w<nworkers;w++) threads.emplace_back(worker_fn, w);
    for(auto& t: threads) t.join();

    double ms = total_ns.load() / 1e6 / ITERS;
    printf("%-25s P=%d: %.3f ms/img\n", name, nworkers, ms);
}

int main() {
    run_parallel("V4 SoA separate ch", true,  1);
    run_parallel("V2 AoS",             false, 1);
    run_parallel("V4 SoA separate ch", true,  5);
    run_parallel("V2 AoS",             false, 5);
}
