struct GenericPool <: Layer
    window::Union{Int,Tuple{Vararg{Int}}}
    padding::Union{Int,Tuple{Vararg{Int}}}
    stride::Union{Int,Tuple{Vararg{Int}}}
    mode::Int
    maxpoolingNanOpt::Int
    alpha::Int
    unpool::Bool
end

GenericPool(;window=2,padding=0,stride=window,mode=0,maxpoolingNanOpt=0,alpha=1,unpool=false) = GenericPool(window,padding,stride,mode,maxpoolingNanOpt,alpha,unpool)

function (m::GenericPool)(x)
     forw = x.unpool ? pool : unpool
     forw(x;window=m.window,padding=m.padding,stride=m.stride,mode=m.mode,maxpoolingNanOpt=m.maxpoolingNanOpt,alpha=m.alpha)
end

"""
    Pool(kwargs...)
    (::GenericPool)(x)

Compute pooling of input values (i.e., the maximum or average of several adjacent
values) to produce an output with smaller height and/or width.

Currently 4 or 5 dimensional KnetArrays with Float32 or Float64 entries are
supported. If x has dimensions (X1,X2,...,I,N), the result y will have dimensions
(Y1,Y2,...,I,N) where

Yi=1+floor((Xi+2*padding[i]-window[i])/stride[i])

Here I is the number of input channels, N is the number of instances, and Xi,Yi
are spatial dimensions. window, padding and stride are keyword arguments that can
be specified as a single number (in which case they apply to all dimensions), or
an array/tuple with entries for each spatial dimension.

Keywords:

* window=2: the pooling window size for each dimension.

* padding=0: the number of extra zeros implicitly concatenated at the
start and at the end of each dimension.

* stride=window: the number of elements to slide to reach the next pooling
window.

* mode=0: 0 for max, 1 for average including padded values, 2 for average
excluding padded values.

* maxpoolingNanOpt=0: Nan numbers are not propagated if 0, they are
propagated if 1.

* alpha=1: can be used to scale the result.

"""
Pool(;o...)   = GenericPool(;o...)

"""
    UnPool(kwargs...)
    (::GenericPool)(x)

    Reverse of pooling. It has same kwargs with Pool

    x == pool(unpool(x;o...); o...)
"""
UnPool(;o...) = GenericPool(;unpool=true,o...)

struct GenericConv <: Layer
    w
    b
    f
    padding::Union{Int,Tuple{Vararg{Int}}}
    stride::Union{Int,Tuple{Vararg{Int}}}
    pool::Union{GenericPool,Nothing}
    upscale
    mode::Int
    alpha
end
GenericConv(h::Int;winit=xavier,binit=zeros,opts...)=GenericConv(Prm(winit(h,1,1,1)),binit(1,1,1,1);opts...)
GenericConv(h::Int,w::Int;winit=xavier,binit=zeros,opts...)=GenericConv(Prm(winit(h,w,1,1)),binit(1,1,1,1);opts...)
GenericConv(h::Int,w::Int,c::Int;winit=xavier,binit=zeros,opts...)=GenericConv(Prm(winit(h,w,c,1)),binit(1,1,1,1);opts...)
GenericConv(h::Int,w::Int,c::Int,o::Int;winit=xavier,binit=zeros,opts...)=GenericConv(Prm(winit(h,w,c,o)),binit(1,1,o,1);opts...)
function GenericConv(w,b;f=identity,stride=1,padding=0,mode=0,upscale=1,alpha=1,pool=nothing,unpool=nothing,deconv=false)
    if typeof(pool) <: Union{Int,Tuple{Vararg{Int}}}
        genericpool = Pool(;window=pool)
    elseif typeof(unpool) <: Union{Int,Tuple{Vararg{Int}}}
        genericpool = UnPool(;window=pool)
    else
        genericpool = nothing
    end
    GenericConv(w,b,f,padding,stride,genericpool,upscale,mode,alpha)
end

function (m::GenericConv)(x)
     n = ndims(x)
     if n == 4 || n==5
     elseif n == 3; x = reshape(x,size(x)...,1)
     elseif n == 2; x = reshape(x,size(x)...,1,1)
     elseif n == 1; x = reshape(x,size(x)...,1,1,1)
     else; error("Conv supports 1,2,3,4,5 D arrays only")
     end
     y  = m.f(conv4(m.w,x;stride=m.stride,padding=m.padding,mode=m.mode,upscale=m.upscale,alpha=m.alpha) .+ m.b)
     yp = m.pool == nothing ? y : m.pool(y);

     n > 3 ? yp : reshape(yp,size(yp)[1:n])
end

"""
    Conv(h,[w,c,o];kwargs...)

Creates and convolutional layer according to given filter dimensions.

    (m::GenericConv)(x) #forward run

If `m.w` has dimensions `(W1,W2,...,I,O)` and
`x` has dimensions `(X1,X2,...,I,N)`, the result `y` will have
dimensions `(Y1,Y2,...,O,N)` where

    Yi=1+floor((Xi+2*padding[i]-Wi)/stride[i])

Here `I` is the number of input channels, `O` is the number of output channels, `N` is the number of instances,
and `Wi,Xi,Yi` are spatial dimensions. `padding` and `stride` are
keyword arguments that can be specified as a single number (in which case they apply to all dimensions),
or an tuple with entries for each spatial dimension.

# Keywords
* `f=identity`: nonlinear function applied after convolution
* `pool=nothing`: Pooling layer or window size of pooling
* `winit=xavier`: weight initialization distribution
* `bias=zeros`: bias initialization distribution
* `padding=0`: the number of extra zeros implicitly concatenated at the start and at the end of each dimension.
* `stride=1`: the number of elements to slide to reach the next filtering window.
* `upscale=1`: upscale factor for each dimension.
* `mode=0`: 0 for convolution and 1 for cross-correlation.
* `alpha=1`: can be used to scale the result.
* `handle`: handle to a previously created cuDNN context. Defaults to a Knet allocated handle.

"""
Conv(x...;o...)   = GenericConv(x...;o...)


"""
    DeConv(h,[w,c,o];kwargs...)

Creates and deconvolutional layer according to given filter dimensions.

    (m::GenericConv)(x) #forward run

If `m.w` has dimensions `(W1,W2,...,I,O)` and
`x` has dimensions `(X1,X2,...,I,N)`, the result `y` will have
dimensions `(Y1,Y2,...,O,N)` where

    Yi = Wi+stride[i](Xi-1)-2padding[i]

Here `I` is the number of input channels, `O` is the number of output channels, `N` is the number of instances,
and `Wi,Xi,Yi` are spatial dimensions. `padding` and `stride` are
keyword arguments that can be specified as a single number (in which case they apply to all dimensions),
or an tuple with entries for each spatial dimension.

# Keywords
* `f=identity`: nonlinear function applied after convolution
* `unpool=nothing`: Unpooling layer or window size of unpooling
* `winit=xavier`: weight initialization distribution
* `bias=zeros`: bias initialization distribution
* `padding=0`: the nßumber of extra zeros implicitly concatenated at the start and at the end of each dimension.
* `stride=1`: the number of elements to slide to reach the next filtering window.
* `upscale=1`: upscale factor for each dimension.
* `mode=0`: 0 for convolution and 1 for cross-correlation.
* `alpha=1`: can be used to scale the result.
* `handle`: handle to a previously created cuDNN context. Defaults to a Knet allocated handle.
"""
DeConv(x...;o...) = GenericConv(x...;deconv=true,o...)
