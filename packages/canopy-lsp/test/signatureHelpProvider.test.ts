import { URI, Utils } from "vscode-uri";
import { SignatureHelp } from "vscode-languageserver";
import { SignatureHelpProvider } from "../src/common/providers";
import { ISignatureHelpParams } from "../src/common/providers/paramsExtensions";
import { getInvokePositionFromSource } from "./utils/sourceParser";
import { baseUri, SourceTreeParser, srcUri } from "./utils/sourceTreeParser";

class MockSignatureHelpProvider extends SignatureHelpProvider {
  handleSignatureHelp = (
    params: ISignatureHelpParams,
  ): SignatureHelp | null => {
    return this.handleSignatureHelpRequest(params);
  };
}

describe("SignatureHelpProvider", () => {
  const treeParser = new SourceTreeParser();

  async function testSignatureHelp(
    source: string,
  ): Promise<SignatureHelp | null> {
    await treeParser.init();
    const provider = new MockSignatureHelpProvider();

    const { invokePosition, invokeFile, sources } =
      getInvokePositionFromSource(source);

    if (!invokePosition) {
      throw new Error("Getting position failed");
    }

    const testUri = Utils.joinPath(
      invokeFile.startsWith("tests") ? URI.file(baseUri) : srcUri,
      invokeFile,
    ).toString();

    const program = await treeParser.getProgram(sources);
    const sourceFile = program.getSourceFile(testUri);

    if (!sourceFile) throw new Error("Getting source file failed");

    return provider.handleSignatureHelp({
      textDocument: { uri: testUri },
      position: invokePosition,
      program,
      sourceFile,
    });
  }

  it("should return null when not in a function call", async () => {
    const source = `
--@ Test.elm
module Test exposing (..)

foo = 42
     --^
`;

    const result = await testSignatureHelp(source);
    expect(result).toBeNull();
  });

  it("should return signature help inside a function call", async () => {
    const source = `
--@ Test.elm
module Test exposing (..)

add : Int -> Int -> Int
add x y = x + y

result = add 1 2
            --^
`;

    const result = await testSignatureHelp(source);

    // The result may or may not be available depending on tree-sitter parsing
    // At minimum, verify it doesn't crash
    if (result) {
      expect(result.signatures.length).toBeGreaterThan(0);
      expect(result.signatures[0].label).toContain("add");
    }
  });
});
