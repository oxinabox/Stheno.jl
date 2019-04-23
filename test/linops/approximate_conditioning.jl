using LinearAlgebra
using Stheno: GPC, PPC, optimal_q, pw, Xt_invA_X, Xt_invA_Y, PseudoPoints

# Test Titsias implementation by checking that it (approximately) recovers exact inference
# when M = N and Z = X.
@testset "Titsias" begin
    @testset "optimal_q (single conditioning)" begin
        @testset "σ²" begin
            rng, N, σ², gpc = MersenneTwister(123456), 10, 1e-1, GPC()
            x = collect(range(-3.0, 3.0, length=N))
            f = GP(sin, eq(), gpc)

            for σ² in [1e-2, 1e-1, 1e0, 1e1]
                @testset "σ² = $σ²" begin
                    y = rand(rng, f(x, σ²))

                    # Compute approximate posterior suff. stats.
                    m_ε, Λ_ε, U = optimal_q(f(x, σ²)←y, f(x))
                    f′ = f | (f(x, σ²) ← y)

                    # Check that exact and approx. posteriors are close in this case.
                    @test m_ε ≈ cholesky(cov(f(x))).U' \ (mean(f′(x)) - mean(f(x)))
                    @test U ≈ cholesky(cov(f(x))).U
                    B = U' \ cov(f(x))
                    @test Λ_ε.U ≈ cholesky(B * B' ./ σ² + I).U
                end
            end
        end
        @testset "Diagonal" begin
            rng, N, gpc = MersenneTwister(123456), 11, GPC()
            x = collect(range(-3.0, 3.0, length=N))
            f = GP(sin, eq(), gpc)
            Σ = Diagonal(exp.(0.1 * randn(rng, N)) .+ 1)
            y = rand(rng, f(x, Σ))

            # Compute approximate posterior suff. stats.
            m_ε, Λ_ε, U = optimal_q(f(x, Σ)←y, f(x))
            f′ = f | (f(x, Σ) ← y)

            # Check that exact and approx. posteriors are close in this case.
            @test m_ε ≈ cholesky(cov(f(x))).U' \ (mean(f′(x)) - mean(f(x)))
            @test U ≈ cholesky(cov(f(x))).U
            B = U' \ cov(f(x))
            @test Λ_ε.U ≈ cholesky(Symmetric(B * (Σ \ B') + I)).U
        end
        @testset "Dense" begin
            rng, N, gpc = MersenneTwister(123456), 10, GPC()
            x = collect(range(-3.0, 3.0, length=N))
            f = GP(sin, eq(), gpc)
            A = 0.1 * randn(rng, N, N)
            Σ = Symmetric(A * A' + I)
            y = rand(rng, f(x, Σ))

            # Compute approximate posterior suff. stats.
            m_ε, Λ_ε, U = optimal_q(f(x, Σ)←y, f(x))
            f′ = f | (f(x, Σ) ← y)

            # Check that exact and approx. posteriors are close in this case.
            @test m_ε ≈ cholesky(cov(f(x))).U' \ (mean(f′(x)) - mean(f(x)))
            @test U ≈ cholesky(cov(f(x))).U
            B = U' \ cov(f(x))
            @test Λ_ε.U ≈ cholesky(Symmetric(B * (cholesky(Σ) \ B') + I)).U
        end
    end
    @testset "optimal_q (multiple conditioning)" begin
        rng, N, N′, σ², gpc = MersenneTwister(123456), 5, 7, 1e-1, GPC()
        xx′ = collect(range(-3.0, stop=3.0; length=N + N′))
        idx = randperm(rng, length(xx′))[1:N]
        idx_1, idx_2 = idx, setdiff(1:length(xx′), idx)
        x, x′ = xx′[idx_1], xx′[idx_2]

        f = GP(sin, eq(), gpc)
        y, y′ = rand(rng, [f(x, σ²), f(x′, σ²)])

        # Compute approximate posterior suff. stats.
        m_ε, Λ_ε, U = optimal_q((f(x, σ²)←y, f(x′, σ²)←y′), f(xx′))
        f′ = f | (f(x, σ²) ← y, f(x′, σ²)←y′)

        # Check that exact and approx. posteriors are close in this case.
        @test m_ε ≈ cholesky(cov(f(xx′))).U' \ (mean(f′(xx′)) - mean(f(xx′)))
        @test U ≈ cholesky(cov(f(xx′))).U
        @test Λ_ε.U ≈ cholesky((U' \ cov(f(xx′))) * (U' \ cov(f(xx′)))' ./ σ² + I).U
    end
    @testset "single conditioning" begin
        rng, N, N′, Nz, σ², gpc = MersenneTwister(123456), 2, 3, 2, 1e-1, GPC()
        x = collect(range(-3.0, 3.0, length=N))
        x′ = collect(range(-3.0, 3.0, length=N′))
        z = x

        # Generate toy problem.
        f = GP(sin, eq(), gpc)
        y = rand(f(x, σ²))

        # Exact conditioning.
        f′ = f | (f(x, σ²)←y)

        # Approximate conditioning that should yield (almost) exact results.
        m_ε, Λ_ε, U = optimal_q(f(x, σ²), y, f(z))
        pp = PseudoPoints(f, PPC(z, U, m_ε, Λ_ε))
        f′_approx = f | pp
        g′_approx = f | pp

        @test mean(f′(x′)) ≈ mean(f′_approx(x′))
        @test cov(f′(x′)) ≈ cov(f′_approx(x′))
        @test cov(f′(x′), f′(x)) ≈ cov(f′_approx(x′), f′_approx(x))
        @test cov(f′(x′), f′(x)) ≈ cov(f′_approx(x′), g′_approx(x))
        @test cov(f′(x′), f′(x)) ≈ cov(g′_approx(x′), f′_approx(x))
    end
    # @testset "multiple conditioning" begin
    #     rng, N, N′, Nz, σ², gpc = MersenneTwister(123456), 11, 10, 11, 1e-1, GPC()
    #     x = collect(range(-3.0, 3.0, length=N))
    #     x′ = collect(range(-3.0, 3.0, length=N′))
    #     x̂ = collect(range(-4.0, 4.0, length=N))
    #     z = copy(x)

    #     # Construct toy problem.
    #     f = GP(sin, eq(), gpc)
    #     y, y′ = rand(rng, [f(x, σ²), f(x′, σ²)])

    #     # Perform approximate inference with concatenated inputs.
    #     f′_concat = f | Titsias(f(vcat(x, x′), σ²)←vcat(y, y′), f(z))

    #     # Perform approximate inference with multiple observations.
    #     f′_multi = f | Titsias((f(x, σ²)←y, f(x′, σ²)←y′), f(z))

    #     # Check that the above agree.
    #     @test mean(f′_concat(x̂)) == mean(f′_concat(x̂))
    #     @test cov(f′_concat(x̂)) == cov(f′_concat(x̂))
    # end
end
