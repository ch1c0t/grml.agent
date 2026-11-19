include JSON::Serializable

property name : String
property status : String = "pending"
property packages : Array(String) = [] of String
property host_executables : Array(String) = [] of String
property recipes : Array(String) = [] of String

def initialize(@name : String)
end
