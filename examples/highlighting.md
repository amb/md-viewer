# Native syntax highlighting

## Swift

~~~swift
// Native colors adapt to light and dark mode.
struct Greeting {
    let message = "Hello, Markdown 👋"
    func show() { print(message) }
}
let count = 42
~~~

## Python

~~~python
def greet(name: str) -> str:
    """A small greeting."""
    return f"Hello, {name}"

# Keep comments separate from strings.
print(greet("World"))
~~~

## Rust

~~~rust
fn main() {
    let message = r#"Hello, "Markdown""#;
    println!("{}", message);
}
~~~

## JavaScript / TypeScript

~~~typescript
interface Document { title: string }
const document: Document = { title: "Markdown" };
console.log(document.title);
~~~

## JSON

~~~json
{"title": "Markdown", "enabled": true, "count": 42}
~~~

## Shell

~~~bash
# Build the native viewer.
if test -n "$HOME"; then
    echo "Ready"
fi
~~~

## SQL

~~~sql
SELECT title, created_at
FROM documents
WHERE archived = false
ORDER BY created_at DESC;
~~~

## HTML and CSS

~~~html
<!-- Inert source text, never executed. -->
<article class="document">Hello</article>
~~~

~~~css
article {
    color: #aabbcc;
    padding: 16px;
}
~~~
