swift package \
    --allow-writing-to-directory ./docs \
    generate-documentation --target SharedTesting \
    --disable-indexing \
    --transform-for-static-hosting \
    --hosting-base-path shared-testing \
    --output-path ./docs
