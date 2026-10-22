#ifndef QUESTLOG_PYTHON_BRIDGE_H
#define QUESTLOG_PYTHON_BRIDGE_H
char *QLPythonInitialize(const char *resources, const char *framework);
char *QLPythonDispatch(const char *request, const char *configuration);
void QLPythonFree(char *value);
#endif
