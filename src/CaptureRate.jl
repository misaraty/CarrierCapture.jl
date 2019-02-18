__precompile__()

push!(LOAD_PATH,"../src/")
module CaptureRate
using Potential
using Polynomials

export conf_coord, cc_from_dict, calc_overlap!, calc_capt_coeff!

ħ = 6.582119514E-16 # eV⋅s
kB  = 8.6173303E-5 # eV⋅K⁻¹

occ_cut_off = 1E-5


mutable struct conf_coord
    # Configuration coordinate
    name::String
    # potentials
    V1::potential; V2::potential
    # e-ph coupling matrix element; degeneracy
    W::Float64; g::Int
    # vibrational wave function overlap integral
    # (initial state) phonon eigenvalue; phonon overlap; Gaussian function energy 
    ϵ_matrix::Array{Float64,2}; overlap_matrix::Array{Float64,2}; δ_matrix::Array{Float64,2}
    temperature::Array{Float64,1}; capt_coeff::Array{Float64,1}
    partial_capt_coeff::Array{Float64, 3}
end
conf_coord(pot_i::potential, pot_f::potential) = conf_coord("", pot_i, pot_f, Inf, 1, 
           Array{Float64}(undef, 0, 0), Array{Float64}(undef, 0, 0), Array{Float64}(undef, 0, 0), 
           [], [], Array{Float64}(undef, 0, 0, 0))


function cc_from_dict(pot_i, pot_f, cfg::Dict)::conf_coord
    cc = conf_coord(pot_i, pot_f)
    cc.name = "$(cfg["initial"]) => $(cfg["final"])"
    cc.W = cfg["W"]
    cc.g = cfg["g"]
    return cc
end

function calc_overlap!(cc::conf_coord; cut_off = 0.25, σ = 0.025)
    ΔL = (maximum(cc.V1.Q) - minimum(cc.V1.Q))/length(cc.V1.Q)
    cc.overlap_matrix = zeros(length(cc.V1.ϵ), length(cc.V2.ϵ))
    cc.δ_matrix = zeros(length(cc.V1.ϵ), length(cc.V2.ϵ))

    for i in UnitRange(1, length(cc.V1.ϵ))
        for j in UnitRange(1, length(cc.V2.ϵ))
            Δϵ = abs(cc.V1.ϵ[i] - cc.V2.ϵ[j])
            if  Δϵ < cut_off
                integrand = (cc.V1.χ[i, :] .* cc.V1.Q .* cc.V2.χ[j, :]) 
                overlap = sum(integrand)*ΔL

                cc.overlap_matrix[i, j] = overlap
                cc.δ_matrix[i, j] = exp(-(Δϵ/σ)^2/2)/(σ*sqrt(2π))
            end
        end
    end
end

function calc_capt_coeff!(cc::conf_coord, V, temperature)
    # TODO:       convergence over σ
    partial_capt_coeff = zeros(length(cc.V1.ϵ), length(cc.V2.ϵ), length(temperature))
    cc.capt_coeff = zeros(length(temperature))
    Z = zeros(length(temperature)) # partition function
    β = 1 ./ (kB * temperature)

    for ϵ in cc.V1.ϵ
        Z = Z + exp.(-β*ϵ)
    end

    for i in 1:length(cc.V1.ϵ)
        for j in 1:length(cc.V2.ϵ)
            ϵ = cc.V1.ϵ[i]
            overlap = cc.overlap_matrix[i, j]
            δ = cc.δ_matrix[i, j]
            occ = exp.(-β*ϵ) ./ Z
            partial_capt_coeff[i, j, :] = occ * overlap .* overlap * δ
        end
    end 
    partial_capt_coeff = V*2π/ħ*cc.g*cc.W^2 * partial_capt_coeff

    replace!(partial_capt_coeff, NaN => 0)
    
    occ_high = exp(-β[end]*cc.V1.ϵ[end]/Z[end])
    
    @assert occ_high < occ_cut_off "occ(ϵ_max, T_max): $occ_high should be less than $occ_cut_off"
    
    cc.capt_coeff = dropdims(sum(partial_capt_coeff, dims = (1, 2)), dims = (1, 2))
    cc.partial_capt_coeff = partial_capt_coeff
    cc.temperature = temperature
end


end # module
