- The `--backend` argument (lines 239-245) and its validation in `main()` (the `if args.backend == "file"` check, lines 254-256)

- A longer inline span: `if args.backend == "file" and args.output is not None and args.input is not None: use_file_backend(args.input, args.output)` followed by ordinary text.

Ordinary paragraph with `inline code` and text after it.

```python
if args.backend == "file":
    use_file_backend(args)
```

Text after the fenced code block.
