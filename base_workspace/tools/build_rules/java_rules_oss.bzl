# Copyright 2014 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

java_filetype = filetype([".java"])
jar_filetype = filetype([".jar"])
srcjar_filetype = filetype([".jar", ".srcjar"])

UNIX_JAVA_PATH = "/usr/bin/"
WINDOWS_JAVA_PATH = "C:/Program\ Files/Java/jdk1.8.0_20/bin/"

def is_windows(config):
  return config.fragment(cpp).compiler.startswith("windows_")

def java_path(ctx):
  if is_windows(ctx.configuration):
    return WINDOWS_JAVA_PATH
  else:
    return UNIX_JAVA_PATH

def path_separator(ctx):
  if is_windows(ctx.configuration):
    return ";"
  else:
    return ":"

# This is a quick and dirty rule to make Bazel compile itself. It's not
# production ready.

def java_library_impl(ctx):
  class_jar = ctx.outputs.class_jar
  compile_time_jars = set(order="link")
  runtime_jars = set(order="link")
  for dep in ctx.targets.deps:
    compile_time_jars += dep.compile_time_jars
    runtime_jars += dep.runtime_jars

  jars = jar_filetype.filter(ctx.files.jars)
  compile_time_jars += jars
  runtime_jars += jars
  compile_time_jars_list = list(compile_time_jars) # TODO: This is weird.

  build_output = class_jar.path + ".build_output"
  sources = ctx.files.srcs

  sources_param_file = ctx.new_file(
      ctx.configuration.bin_dir, class_jar, "-2.params")
  ctx.file_action(
      output = sources_param_file,
      content = cmd_helper.join_paths("\n", set(sources)),
      executable = False)

  javapath = java_path(ctx)

  # Cleaning build output directory
  cmd = "set -e;rm -rf " + build_output + ";mkdir " + build_output + "\n"
  if ctx.files.srcs:
    cmd += javapath + "javac"
    if compile_time_jars:
      cmd += " -classpath '" + cmd_helper.join_paths(path_separator(ctx), compile_time_jars) + "'"
    cmd += " -d " + build_output + " @" + sources_param_file.path + "\n"

  # We haven't got a good story for where these should end up, so
  # stick them in the root of the jar.
  for r in ctx.files.resources:
    cmd += "cp %s %s\n" % (r.path, build_output)
  cmd += (javapath + "jar cf " + class_jar.path + " -C " + build_output + " .\n" +
         "touch " + build_output + "\n")
  ctx.action(
    inputs = (sources + compile_time_jars_list + [sources_param_file] +
              ctx.files.resources),
    outputs = [class_jar],
    mnemonic='Javac',
    command=cmd,
    use_default_shell_env=True)

  runfiles = ctx.runfiles(collect_data = True)

  return struct(files = set([class_jar]),
                compile_time_jars = compile_time_jars + [class_jar],
                runtime_jars = runtime_jars + [class_jar],
                runfiles = runfiles)


def java_binary_impl(ctx):
  library_result = java_library_impl(ctx)

  deploy_jar = ctx.outputs.deploy_jar
  manifest = ctx.outputs.manifest
  build_output = deploy_jar.path + ".build_output"
  main_class = ctx.attr.main_class
  ctx.file_action(
    output = manifest,
    content = "Main-Class: " + main_class + "\n",
    executable = False)

  javapath = java_path(ctx)

  # Cleaning build output directory
  cmd = "set -e;rm -rf " + build_output + ";mkdir " + build_output + "\n"
  for jar in library_result.runtime_jars:
    cmd += "unzip -qn " + jar.path + " -d " + build_output + "\n"
  cmd += (javapath + "jar cmf " + manifest.path + " " +
         deploy_jar.path + " -C " + build_output + " .\n" +
         "touch " + build_output + "\n")

  ctx.action(
    inputs=list(library_result.runtime_jars) + [manifest],
    outputs=[deploy_jar],
    mnemonic='Deployjar',
    command=cmd,
    use_default_shell_env=True)

  # Write the wrapper.
  executable = ctx.outputs.executable
  ctx.file_action(
    output = executable,
    content = '\n'.join([
        "#!/bin/bash",
        "# autogenerated - do not edit.",
        "case \"$0\" in",
        "/*) self=\"$0\" ;;",
        "*)  self=\"$PWD/$0\";;",
        "esac",
        "",
        "if [[ -z \"$JAVA_RUNFILES\" ]]; then",
        "  if [[ -e \"${self}.runfiles\" ]]; then",
        "    export JAVA_RUNFILES=\"${self}.runfiles\"",
        "  fi",
        "  if [[ -n \"$JAVA_RUNFILES\" ]]; then",
        "    export TEST_SRCDIR=${TEST_SRCDIR:-$JAVA_RUNFILES}",
        "  fi",
        "fi",
        "",

        # We extract the .so into a temp dir. If only we could mmap
        # directly from the zip file.
        "DEPLOY=$(dirname $self)/$(basename %s)" % deploy_jar.path,

        # This works both on Darwin and Linux, with the darwin path
        # looking like tmp.XXXXXXXX.{random}
        "SO_DIR=$(mktemp -d -t tmp.XXXXXXXXX)",
        "function cleanup() {",
        "  rm -rf ${SO_DIR}",
        "}",
        "trap cleanup EXIT",
        "unzip -q -d ${SO_DIR} ${DEPLOY} \"*.so\" \"*.dll\" \"*.dylib\" >& /dev/null",
        ("java -Djava.library.path=${SO_DIR} %s -jar $DEPLOY \"$@\""
         % ' '.join(ctx.attr.jvm_flags)) ,
        "",
        ]),
    executable = True)

  runfiles = ctx.runfiles(files = [deploy_jar, executable], collect_data = True)
  files_to_build = set([deploy_jar, manifest, executable])
  files_to_build += library_result.files

  return struct(files = files_to_build, runfiles = runfiles)

def java_import_impl(ctx):
  # TODO: Why do we need to filter here? The attribute already says only jars are allowed.
  jars = set(jar_filetype.filter(ctx.files.jars))
  runfiles = ctx.runfiles(collect_data = True)
  return struct(files = jars,
                compile_time_jars = jars,
                runtime_jars = jars,
                runfiles = runfiles)


java_library_attrs = {
    "data": attr.label_list(
        allow_files=True,
        allow_rules=False,
        cfg=DATA_CFG),
    "resources": attr.label_list(allow_files=True),
    "srcs": attr.label_list(allow_files=java_filetype),
    "jars": attr.label_list(allow_files=jar_filetype),
    "deps": attr.label_list(
        allow_files=False,
        providers = ["compile_time_jars", "runtime_jars"]),
    }

java_library = rule(
    java_library_impl,
    attrs = java_library_attrs,
    outputs = {
        "class_jar": "lib%{name}.jar",
    })

java_binary_attrs = {
    "main_class": attr.string(mandatory=True),
    "jvm_flags": attr.string_list(),
} + java_library_attrs

java_binary_outputs = {
    "class_jar": "lib%{name}.jar",
    "deploy_jar": "%{name}_deploy.jar",
    "manifest": "%{name}_MANIFEST.MF"
}

java_binary = rule(java_binary_impl,
   executable = True,
   attrs = java_binary_attrs,
   outputs = java_binary_outputs)

java_test = rule(java_binary_impl,
   executable = True,
   attrs = java_library_attrs + {
       "main_class": attr.string(default="org.junit.runner.JUnitCore"),
       # TODO(bazel-team): it would be better if we could offer a
       # test_class attribute instead, but this attribute is hard
       # coded in the bazel infrastructure.
       "args": attr.string_list(),
       "jvm_flags": attr.string_list(),
   },
   outputs = java_binary_outputs,
   test = True,
)

java_import = rule(
    java_import_impl,
    attrs = {
        "jars": attr.label_list(allow_files=jar_filetype),
        "srcjar": attr.label(allow_files=srcjar_filetype),
    })
