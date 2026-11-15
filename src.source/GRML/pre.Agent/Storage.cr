DISK_NAME_PATTERN = /\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/
DISK_SIZE_PATTERN = /\A[1-9][0-9]*(?:[KMGTP])?\z/i
DISK_FORMATS = ["qcow2", "raw"]

include Public
include Private
