module CaptureRate

push!(LOAD_PATH, ".")

using Phonon: harmonic, solve1D_ev_amu
using Plots

ħ = 6.582119514E-16 # eV⋅s
kB = 8.6173303E-5 # eV⋅K⁻¹

V = 1.1E-21 # Å³ volume
g = 1       # degeneracy
W = 0.204868962802   # ev/(amu^(1/2)*Å)


mutable struct potential
    Q # Configuration coordinate
    E # Energy
end

mutable struct CC
    # Configuration coordinate
    # potentials
    V1; V2
    # eigenvalue and eigenvectors.
    ϵ1; ϵ2
    χ1; χ2
    # vibrational wave function overlap integral
    # (initial state) phonon eigenvalue; phonon overlap; Gaussian function energy 
    ϵ_list; overlap_list; δ_list
end
CC() = CC([], [], [], [], [], [], [], [], [])

function calc_harm_wave_func(ħω1, ħω2, ΔQ, ΔE; Qi=-10, Qf=10, NQ=100, nev=10)
    # potentials
    x = linspace(Qi, Qf, NQ)

    # define potential
    # Ground state
    E1 = harmonic(x, ħω1)
    V1 = potential(x, E1)
    # Excited state
    E2 = harmonic(x-ΔQ, ħω2)+ΔE
    V2 = potential(x, E2)

    # solve Schrödinger equation
    # Ground state
    ϵ1, χ1 = solve1D_ev_amu(x->harmonic(x, ħω1), NQ=NQ, Qi=Qi, Qf=Qf, nev=nev)
    # Excited state
    ϵ2, χ2 = solve1D_ev_amu(x->harmonic(x-ΔQ, ħω2), NQ=NQ, Qi=Qi, Qf=Qf, nev=nev)
    ϵ2 += ΔE

    # Assign
    cc = CC()
    cc.V1 = V1; cc.V2 = V2
    cc.ϵ1 = ϵ1; cc.χ1 = χ1
    cc.ϵ2 = ϵ2; cc.χ2 = χ2
    cc
end 

function plot_potentials(cc::CC; plot_wf=false)
    # Initial state
    plot(cc.V1.Q, cc.V1.E, lw=4, color="black")    
    # Final state
    plot!(cc.V2.Q, cc.V2.E, lw=4, color="black")

    # plot wave functions
    if plot_wf
        # Initial state
        for i = 1:length(cc.ϵ1)
            plot!(cc.V1.Q, cc.χ1[i]*1E-1+cc.ϵ1[i], color="#d73027")
        end
        # Final state
        for i = 1:length(cc.ϵ2)
            plot!(cc.V2.Q, cc.χ2[i]*1E-1+cc.ϵ2[i], color="#4575b4")
        end
    end
end

function calc_overlap!(cc::CC; cut_off=0.25, σ=0.025)
    p = plot_potentials(cc)
    ΔL = (maximum(cc.V1.Q) - minimum(cc.V1.Q))/length(cc.V1.Q)
    cc.ϵ_list = []
    cc.overlap_list = []
    cc.δ_list = []
    for i in range(1, length(cc.ϵ1))
        for j in range(1, length(cc.ϵ2))
            Δϵ = abs(cc.ϵ1[i] - cc.ϵ2[j])
            if  Δϵ < cut_off
                integrand = (cc.χ1[i] .* cc.V1.Q .* cc.χ2[j]) 
                overlap = sum(integrand)*ΔL

                append!(cc.ϵ_list, cc.ϵ1[i])
                append!(cc.overlap_list, overlap)

                append!(cc.δ_list, exp(-(Δϵ/σ)^2/2)/(σ*sqrt(2*π)))

                # plot
                alpha = (cut_off-Δϵ)/cut_off
                plot!(cc.V1.Q, cc.ϵ1[i]+integrand*1E-1, color="#31a354", lw=3, alpha=alpha)

            end
        end
    end
    return(p)
end

function calc_capt_coeff(W, V, T_range, cc::CC)
    capt_coeff = zeros(length(T_range))
    # TODO: CHECK convergence of the partition function Z(number of eigenvalue)
    # TODO:       convergence over σ
    Z = 0
    β = 1 ./ (kB .* T_range)
    for ϵ in cc.ϵ1
        Z+=exp.(-β*ϵ)
    end
    # println('Z', Z)
    for summand in zip(cc.ϵ_list, cc.overlap_list, cc.δ_list)
        ϵ, overlap, δ = summand
        occ = exp.(-β*ϵ) ./ Z
        capt_coeff += occ * overlap .* overlap * δ
    end
    capt_coeff = V*2*π/ħ*g*W^2 * capt_coeff
    return capt_coeff
end


end # module