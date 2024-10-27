load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

cc_library(
    name = "HLSObjcModuleBinding",
    srcs = [
    ],
    hdrs = glob([
        "hlsobjcmodule/PublicHeaders/**/*.h",
        "hlsobjcmodule/HLSObjccppModule/PublicHeaders/**/*.h",
    ]),
    includes = [
        "PublicHeaders",
    ],
    copts = [
        "-std=c++17",
    ],
    deps = [
    ],
    visibility = ["//visibility:public"],
    linkstatic = 1,
)

objc_library(
    name = "HLSObjcModule",
    enable_modules = True,
    module_name = "HLSObjcModule",
    srcs = glob([
        "hlsobjcmodule/Sources/**/*.m",
        "hlsobjcmodule/Sources/**/*.h",
        "hlsobjcmodule/HLSObjccppModule/Sources/**/*.mm",
        "hlsobjcmodule/HLSObjccppModule/Sources/**/*.cpp",
        "hlsobjcmodule/HLSObjccppModule/Sources/**/*.h",
    ]),
    hdrs = glob([
        "hlsobjcmodule/PublicHeaders/**/*.h",
        "hlsobjcmodule/HLSObjccppModule/PublicHeaders/**/*.h",
    ]),
    includes = [
        "hlsobjcmodule/HLSObjccppModule/PublicHeaders",
        "hlsobjcmodule/PublicHeaders",
    ],
    copts = [
        "-I{}/hlsobjcmodule/Sources".format(package_name()),
    ],
    deps = [
        "//submodules/ffmpeg:ffmpeg"
    ],
    sdk_frameworks = [
        "Foundation",
        "AVFAudio",
        "CoreGraphics",
        "Metal",
    ],
    visibility = [
        "//visibility:public",
    ],
)
