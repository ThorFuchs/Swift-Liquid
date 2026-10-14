# Values and JSON

Use typed Sendable values and preserve object member order.

## Swift literals

``LiquidValue`` supports string, integer, floating-point, Boolean, nil, array,
and object literals. ``LiquidObject`` retains the insertion order of its entries.
Repeated literal keys replace the value at the original position.

```swift
let context: LiquidObject = [
    "name": "Ada",
    "active": true,
    "roles": ["author", "editor"]
]
```

Only nil and false are falsy. Zero, empty strings, and empty collections are
truthy in Liquid. This differs from many other programming languages.

## JSON input

The JSON convenience reads a complete document, preserves object order, and
rejects malformed syntax, duplicate keys, trailing bytes, excessive depth, and
non-finite numbers.

```swift
let value = try LiquidValue(json: #"{"name":"Ada","active":true}"#)
```

Numbers use Swift Int or finite Double. Exact large decimal arithmetic is outside
this input model; encode exact application data as strings when appropriate.
The sibling Swift-JSON package supplies an exact JSON data model.
