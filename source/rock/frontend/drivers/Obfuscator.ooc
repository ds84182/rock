import io/[FileReader]
import text/[StringTokenizer]
import structs/[ArrayList, HashMap]

import Driver
import rock/frontend/[BuildParams, CommandLine]
import rock/middle/[Module, ClassDecl, TypeDecl, FunctionDecl, VariableDecl, StructLiteral, FunctionCall, PropertyDecl, VariableAccess]

ObfuscationTarget: class {
    oldName: String
    newName: String
    init: func (=oldName, =newName)
}
//
// At this point, this is more like a hack than anything else. We should probably
// defer the obfuscation to a AST walk just before the C-generation pass.
//
Obfuscator: class extends Driver {
    targets: HashMap<String, ObfuscationTarget>
    init: func(.params, mappingFile: String) {
        super(params)
        targets = parseMappingFile(mappingFile)
    }
    compile: func (module: Module) -> Int {
        "Obfuscating..." printfln()
        for (currentModule in module collectDeps())
            processModule(currentModule)
        processModule(module)
        CommandLine success(params)
        "Compiling..." printfln()
        params driver compile(module)
    }
    processModule: func (module: Module) {
        target := targets get(module simpleName)
        if (target != null) {
            module simpleName = target newName
            module underName = module underName substring(0, module underName indexOf(target oldName)) append(target newName)
            module isObfuscated = true
            for (statement in module body) {
                if (statement instanceOf?(VariableDecl) && !statement as VariableDecl getType() instanceOf?(AnonymousStructType)) {
                    vd := statement as VariableDecl
                    if (vd isExtern() && !vd isProto())
                        continue
                    if (vd name contains?(target oldName))
                        vd name = vd name replaceAll(target oldName, target newName)
                }
            }
        }
        // For now, this must live outside the above if-statement, since obfuscation targets may
        // be present in non-target modules.
        for (type in module types) {
            targetType := targets get(type name)
            if (targetType != null) {
                if (type variables size > 0)
                    handleMemberVariables(type, targetType oldName + ".")
                if (type functions size > 0)
                    handleMemberFunctions(type, targetType oldName substring(0, targetType oldName length() - 5) + ".")
                type name = targetType newName
            }
        }
    }
    handleMemberFunctions: func (owner: TypeDecl, searchKeyPrefix: String) {
        for (function in owner functions) {
            functionSearchKey := searchKeyPrefix + function name
            targetFunction := targets get(functionSearchKey)
            if (targetFunction != null) {
                if (function isAbstract || function isVirtual) {
                    CommandLine warn("Obfuscator: abstract and virtual functions are not yet supported.")
                    continue
                }
                function name = targetFunction newName
            }
            handleFunctionArguments(function, searchKeyPrefix)
        }
    }
    handleMemberVariables: func (owner: TypeDecl, searchKeyPrefix: String) {
        for (variable in owner variables) {
            variableSearchKey := searchKeyPrefix + variable name
            if (variable instanceOf?(PropertyDecl))
                handleProperty(variable as PropertyDecl, variableSearchKey)
            else {
                targetVariable := targets get(variableSearchKey)
                if (targetVariable != null)
                    variable name = targetVariable newName
            }
        }
    }
    handleProperty: func (property: PropertyDecl, propertySearchKey: String) {
        targetProperty := targets get(propertySearchKey)
        if (targetProperty != null) {
            obfuscateProperty := func (accept: Bool, target: PropertyDecl, fn: FunctionDecl) {
                if (accept) {
                    // For now, use only partial prefix and strip the suffix
                    target name = targetProperty newName
                    fn name = fn name substring(2, 5) + targetProperty newName
                }
            }
            obfuscateProperty(property getter != null, property, property getter)
            obfuscateProperty(property setter != null, property, property setter)
        }
    }
    handleFunctionArguments: func(function: FunctionDecl, searchKeyPrefix: String) {
        for (variable in function args) {
            variableSearchKey := searchKeyPrefix + variable name
            targetVariable := targets get(variableSearchKey)
            if (targetVariable != null)
                variable name = targetVariable newName
        }
    }
    parseMappingFile: func (mappingFile: String) -> HashMap<String, ObfuscationTarget> {
        result := HashMap<String, ObfuscationTarget> new(15)
        reader := FileReader new(mappingFile)
        content := ""
        while (reader hasNext?())
            content = content append(reader read())
        reader close()
        targets := content split('\n')
        for (target in targets) {
            temp := target split(':')
            if (temp size > 1) {
                result put(temp[0], ObfuscationTarget new(temp[0], temp[1]))
                if (!temp[0] contains?('.'))
                    result put(temp[0] + "Class", ObfuscationTarget new(temp[0] + "Class", temp[1] + "Class"))
            }
        }
        result
    }
}
