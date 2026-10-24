add_application(Hello
    hello.c
    CONSOLE
)

# Keep the binary small: drop unused sections and MacsBug symbol names.
target_compile_options(Hello PRIVATE -ffunction-sections)
set_target_properties(Hello PROPERTIES LINK_FLAGS "-Wl,-gc-sections -Wl,--mac-strip-macsbug")
