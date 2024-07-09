module AntibodyMethodsDoseResponseRecipes

using RecipesBase
using Printf
using FittingObjectiveFunctions
using AdaptiveDensityApproximation
using AntibodyMethodsDoseResponse





####################################################################################################
# Auxiliary functions
####################################################################################################

# Get the indices where (depending on filter_zeros) x and y are non-zero.
function non_zero_indices(x,y,filter_zeros)

	if length(x) != length(y)
		throw(DimensionMismatch("Internal error with filter_zeros: Different number of x-arguments and y-arguments."))
	end

	if filter_zeros[1] && filter_zeros[2]
		indices = [i for i in 1:length(x) if !iszero(x[i]) && !iszero(y[i])]
	elseif filter_zeros[1]
		indices = [i for i in 1:length(x) if !iszero(x[i])]
	elseif filter_zeros[2]
		indices = [i for i in 1:length(y) if !iszero(y[i])]
	else
		indices = collect(1:length(x))
	end
	return indices
end



function grid_points(grid::AdaptiveDensityApproximation.OneDimGrid, volume_normalization)
	centers, volumes, weights = export_all(grid)
	
	base_points = promote_type(eltype(centers), eltype(volumes), Float64)[]
	values = eltype(weights)[]

	for i in 1:length(centers)
		push!(base_points, centers[i] - volumes[i]/2)
		push!(base_points, centers[i] + volumes[i]/2)


		if volume_normalization == :linear
			push!(values, weights[i]/volumes[i], weights[i]/volumes[i])
		elseif volume_normalization == :log
			log_volume = log10(centers[i] + volumes[i]/2) - log10(centers[i] - volumes[i]/2)
			push!(values,weights[i]/log_volume, weights[i]/ log_volume)
		else
			push!(values,weights[i], weights[i])
		end
	end
	return base_points, values
end




function uncertainty_options(n::Integer,colors, opacities)
	if length(colors) < n
		fill_color = colors[end]
		colors = [colors...]
		push!(colors,[fill_color for i in 1:(n-length(colors))]...)
	end

	if length(opacities) < n
		fill_opacity = opacities[end]
		opacities = [opacities...]
		push!(opacities,[fill_opacity for i in 1:(n-length(opacities))]...)
	end
	return colors, opacities
end



















####################################################################################################
# Plotting recipe for dose-response measurement data
####################################################################################################


@recipe function f(data::FittingData; filter_zeros = [true,false])
	
	# Select non-zero data points (depending on filter_zeros).
	indices = non_zero_indices(data.independent,data.dependent,filter_zeros)

	if !isnothing(data.errors)
		yerror --> data.errors[indices]
	end

	return data.independent[indices], data.dependent[indices]
end




@recipe function f(result::DoseResponseResult; filter_zeros = [true,false])

	# Select non-zero data points (depending on filter_zeros).
	indices = non_zero_indices(result.concentrations,result.responses, filter_zeros)

	return result.concentrations[indices], result.responses[indices]
end




@recipe function f(dr_uncertainty::DoseResponseUncertainty; filter_zeros = [true,false], colors = [:gray], opacities = [1.0], reverse = false, hide_labels=true)
	
	if reverse
		levels = dr_uncertainty.levels[end:-1:1]
		lower = dr_uncertainty.lower[end:-1:1,:]
		upper = dr_uncertainty.upper[end:-1:1,:]
		# Opacities and colors need to be reordered before using uncertainty_options(), which repeats the last element if need be.
		opacities = opacities[end:-1:1]
		colors = colors[end:-1:1]
	else
		levels = dr_uncertainty.levels
		lower = dr_uncertainty.lower
		upper = dr_uncertainty.upper
	end

	concentrations = dr_uncertainty.concentrations
	colors, opacities = uncertainty_options(length(levels),colors, opacities)


	for i in eachindex(levels)
		@series begin
			seriestype := :path
			color := colors[i]
			linealpha := opacities[i]
			fillcolor := colors[i]
			fillalpha := opacities[i]
			fillrange := lower[i,:]
			label := hide_labels ? nothing : @sprintf("%.2e",levels[i])

			indices = non_zero_indices(concentrations, upper[i,:], filter_zeros)
			return concentrations[indices],upper[i,indices]
		end
	end
end


















####################################################################################################
# Plotting Kd density grid
####################################################################################################

export DensityPlot, DensityAnnotations

# Wrapper struct to avoid dispatch conflict with AdaptiveDensityApproximationRecipes.
mutable struct DensityPlot
	grid::AdaptiveDensityApproximation.OneDimGrid
end

# Wrapper struct to avoid dispatch conflict with AdaptiveDensityApproximationRecipes.
mutable struct DensityAnnotations
	grid::AdaptiveDensityApproximation.OneDimGrid
end





@recipe function f(grid_wrapper::DensityPlot; volume_normalization = :log)
	return  grid_points(grid_wrapper.grid, volume_normalization)
end







@recipe function f(grid_wrapper::DensityAnnotations; volume_normalization = :log, annotation_bins = [], annotation_size = 10, annotation_offset = 0.05, annotation_x_shift = 0, hover_points = false, annotation_color = :black)

	base_points, values =  grid_points(grid_wrapper.grid, volume_normalization)

	x_positions = [b[1] for b in annotation_bins]

	y_positions = Float64[]
	y_max = maximum(values)

	
	if length(annotation_x_shift) == 1
		annotation_x_shift = [annotation_x_shift[1] for i in eachindex(x_positions)]
	elseif length(annotation_x_shift) != length(annotation_bins)
		throw(DimensionMismatch("Length of annotation_x_shift does not match the length of annotation_bins."))
	end

	if length(annotation_offset) == length(annotation_bins)
		push!(y_positions,((1 .- annotation_offset) .* y_max)...)

	elseif length(annotation_offset)==1
		for i in 1:length(x_positions)
			if isodd(i)
				push!(y_positions,y_max)
			else
				push!(y_positions,(1-annotation_offset[1])*y_max)
			end
		end
	else
		throw(DimensionMismatch("Length of annotation_offset does not match the length of annotation_bins."))
	end


	labels = []
	for i in 1:length(x_positions)
		val = sum(grid_wrapper.grid, lower = annotation_bins[i][1], upper = annotation_bins[i][2])
		push!(labels, @sprintf("%.2e", val))
	end
	annotation_labels = [(l,annotation_color,:left,annotation_size) for l in labels]
	
	
	if hover_points
		for i in 1:length(x_positions)
			@series begin
				seriestype := :scatter
				label := nothing
				markershape := :cross
				hover := [labels[i]]
				return [x_positions[i]], [y_max]
			end
		end
	end

	seriestype := :path
	linestyle := :dash
	linecolor := annotation_color
	linealpha := 0.5
	label := nothing
	annotations --> [[x_positions[i] + annotation_x_shift[i],y_positions[i], annotation_labels[i]] for i in 1:length(x_positions)]

	return [[x,x] for x in vcat(annotation_bins...)], [[0,y_max] for x in vcat(annotation_bins...)]

end











@recipe function f(grid::AdaptiveDensityApproximation.OneDimGrid, epitope_uncertainty::EpitopeUncertainty; volume_normalization = :log, colors = [:gray], opacities = [1.0], reverse = false, hide_labels = true, bins = nothing, bin_color = :gray)

	if reverse
		levels = epitope_uncertainty.levels[end:-1:1]
		lower = epitope_uncertainty.lower[end:-1:1,:]
		upper = epitope_uncertainty.upper[end:-1:1,:]
		# Opacities and colors need to be reordered before using uncertainty_options(), which repeats the last element if need be.
		opacities = opacities[end:-1:1]
		colors = colors[end:-1:1]
	else
		levels = epitope_uncertainty.levels
		lower = epitope_uncertainty.lower
		upper = epitope_uncertainty.upper
	end

	colors, opacities = uncertainty_options(length(levels),colors, opacities)
	temp_grid = deepcopy(grid)
	y_max = 0

	for i in eachindex(levels)
		base_points,lower_values = grid_points(import_weights!(temp_grid,lower[i,:]), volume_normalization)
		base_points,upper_values = grid_points(import_weights!(temp_grid,upper[i,:]), volume_normalization)
		y_max = max.(maximum(upper_values),y_max)

		@series begin

			seriestype := :path
			color := colors[i]
			linealpha := opacities[i]
			fillcolor := colors[i]
			fillalpha := opacities[i]
			fillrange := lower_values
			label := hide_labels ? nothing : @sprintf("%.2e",epitope_uncertainty.levels[i])
			return base_points, upper_values
		end
	end

	if !isnothing(bins)
		centers, volumes, weights = export_all(grid)

		for bin in bins

			# left bin marker:
			ind = minimum(bin)
			x =  centers[ind] - 0.5 * volumes[ind]
			@series begin
				seriestype := :path
				linestyle := :dash
				linecolor := bin_color
				label := nothing
				return [x,x], [0,y_max]
			end

			# right bin marker:
			ind = maximum(bin)
			x =  centers[ind] + 0.5 * volumes[ind]
			@series begin
				seriestype := :path
				linestyle := :dash
				linecolor := bin_color
				label := nothing
				return [x,x], [0,y_max]
			end
		end
	end

	return nothing
end




end

