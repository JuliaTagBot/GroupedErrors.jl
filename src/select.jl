struct Selector{T, F1<:Function, F2<:Function, F3<:Function, F4<:Function, F5<:Function}
    table::T
    splitby::F1
    compare::F2
    across::F3
    x::F4
    y::F5
    kw::Dict{Symbol, Any}
end

Selector(df) = Selector(df, t -> ("y1",), t -> (),t -> 0.0, t -> 0.0, t -> NaN, Dict{Symbol, Any}(:compare => false))

Base.convert(::Type{Selector}, a::Selector) = a
Base.convert(::Type{Selector}, a) = Selector(a)

struct Table2Process{T}
    table::T
    kw::Dict{Symbol, Any}
end

Table2Process(table) = Table2Process(table, Dict{Symbol, Any}())

function Table2Process(s::Selector)
    enumerable = TableTraits.getiterator(s.table)
    T = eltype(enumerable)
    splitter = Base._return_type(s.splitby, Tuple{T,})<:Tuple ?
        t -> s.splitby(t) : t -> (s.splitby(t),)
    if s.kw[:compare]
        select_func = t -> (splitter(t)..., s.compare(t), s.across(t), s.x(t), s.y(t))
    else
        select_func = t -> (splitter(t)..., s.across(t), s.x(t), s.y(t))
    end
    column_types = Base._return_type(select_func, Tuple{T,}).parameters
    columns = Tuple(S[] for S in column_types)
    fill_cols!(columns, enumerable, select_func)
    Table2Process(Tuple(convert_missing.(t) for t in columns), s.kw)
end

struct ProcessedTable{T}
    table::T
    kw::Dict{Symbol, Any}
end

ProcessedTable(t::Table2Process) = pipeline(t)
ProcessedTable(s::Selector) = ProcessedTable(Table2Process(s))

@generated function fill_cols!(columns, enumerable, select_func)
    push_exprs = Expr(:block)
    for i in find(collect(columns.types) .!= Void)
        ex = quote
            j = select_func(i)
            push!(columns[$i], j[$i])
        end
        push!(push_exprs.args, ex)
    end

    quote
        for i in enumerable
            $push_exprs
        end
    end
end

convert_missing(el) = el
convert_missing(el::DataValue{T}) where {T} = isnull(el) ? error("Missing data of type $T is not supported") : el.value
convert_missing(el::DataValue{<:AbstractString}) = get(el, "")
convert_missing(el::DataValue{Symbol}) = get(el, Symbol())
convert_missing(el::DataValue{<:Real}) = get(convert(DataValue{Float64}, el), NaN)
