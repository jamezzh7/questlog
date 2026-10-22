#define PY_SSIZE_T_CLEAN
#include <Python/Python.h>
#import <Foundation/Foundation.h>
#import "PythonBridge.h"

static BOOL initialized = NO;

static char *failure(NSString *message) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"status": @500, @"body": @{@"error": message ?: @"Runtime error"}} options:0 error:nil];
    return strdup([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
}

char *QLPythonInitialize(const char *resources, const char *framework) {
    if (initialized) return NULL;
    @autoreleasepool {
        PyConfig config;
        PyConfig_InitIsolatedConfig(&config);
        config.write_bytecode = 0;
        config.site_import = 0;
        config.install_signal_handlers = 0;
        config.parse_argv = 0;
        config.module_search_paths_set = 1;
        PyStatus status = PyConfig_SetBytesString(&config, &config.home, framework);
        NSString *home = [NSString stringWithUTF8String:framework];
        NSArray<NSString *> *paths = @[[home stringByAppendingPathComponent:@"lib/python3.13"],
                                      [home stringByAppendingPathComponent:@"lib/python3.13/lib-dynload"],
                                      [NSString stringWithUTF8String:resources]];
        for (NSString *path in paths) {
            if (PyStatus_Exception(status)) break;
            wchar_t *wide = Py_DecodeLocale(path.fileSystemRepresentation, NULL);
            if (!wide) { PyConfig_Clear(&config); return failure(@"Unable to configure the bundled runtime"); }
            status = PyWideStringList_Append(&config.module_search_paths, wide);
            PyMem_RawFree(wide);
        }
        if (!PyStatus_Exception(status)) status = Py_InitializeFromConfig(&config);
        NSString *error = PyStatus_Exception(status) ? [NSString stringWithUTF8String:status.err_msg ?: "Unable to initialize the bundled runtime"] : nil;
        PyConfig_Clear(&config);
        if (error) return failure(error);
        initialized = YES;
        PyEval_SaveThread();
        return NULL;
    }
}

char *QLPythonDispatch(const char *request, const char *configuration) {
    @autoreleasepool {
        if (!initialized) return failure(@"Bundled runtime is not initialized");
        PyGILState_STATE state = PyGILState_Ensure();
        PyObject *module = PyImport_ImportModule("store_api");
        PyObject *function = module ? PyObject_GetAttrString(module, "dispatch") : NULL;
        PyObject *value = function ? PyObject_CallFunction(function, "ss", request, configuration) : NULL;
        char *result = NULL;
        if (value && PyUnicode_Check(value)) {
            const char *text = PyUnicode_AsUTF8(value);
            if (text) result = strdup(text);
        }
        if (!result) {
            PyObject *type = NULL, *error = NULL, *trace = NULL;
            PyErr_Fetch(&type, &error, &trace);
            PyErr_NormalizeException(&type, &error, &trace);
            PyObject *description = error ? PyObject_Str(error) : NULL;
            const char *text = description ? PyUnicode_AsUTF8(description) : NULL;
            result = failure(text ? [NSString stringWithUTF8String:text] : @"Invalid runtime response");
            Py_XDECREF(description); Py_XDECREF(type); Py_XDECREF(error); Py_XDECREF(trace);
            PyErr_Clear();
        }
        Py_XDECREF(value); Py_XDECREF(function); Py_XDECREF(module);
        PyGILState_Release(state);
        return result;
    }
}

void QLPythonFree(char *value) { free(value); }
