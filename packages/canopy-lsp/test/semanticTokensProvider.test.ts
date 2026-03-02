import { URI, Utils } from "vscode-uri";
import { SemanticTokens } from "vscode-languageserver";
import { SemanticTokensProvider, semanticTokensLegend } from "../src/common/providers";
import { ISemanticTokensParams } from "../src/common/providers/paramsExtensions";
import { getSourceFiles } from "./utils/sourceParser";
import { baseUri, SourceTreeParser, srcUri } from "./utils/sourceTreeParser";

class MockSemanticTokensProvider extends SemanticTokensProvider {
  handleSemanticTokens = (
    params: ISemanticTokensParams,
  ): SemanticTokens => {
    return this.handleSemanticTokensFull(params);
  };
}

describe("SemanticTokensProvider", () => {
  const treeParser = new SourceTreeParser();

  async function getTokens(source: string): Promise<SemanticTokens> {
    await treeParser.init();
    const provider = new MockSemanticTokensProvider();

    const sources = getSourceFiles(source);
    const fileName = Object.keys(sources)[0];
    const testUri = Utils.joinPath(srcUri, fileName).toString();

    const program = await treeParser.getProgram(sources);
    const sourceFile = program.getSourceFile(testUri);

    if (!sourceFile) throw new Error("Getting source file failed");

    return provider.handleSemanticTokens({
      textDocument: { uri: testUri },
      program,
      sourceFile,
    });
  }

  it("should return semantic tokens for a module", async () => {
    const source = `
--@ Test.elm
module Test exposing (..)

type Color = Red | Green | Blue

greet : String -> String
greet name = "Hello " ++ name
`;

    const tokens = await getTokens(source);
    // SemanticTokens.data is an array of integers encoding tokens
    expect(tokens.data).toBeDefined();
    expect(tokens.data.length).toBeGreaterThan(0);
  });

  it("should return empty tokens for empty module", async () => {
    const source = `
--@ Test.elm
module Test exposing (..)
`;

    const tokens = await getTokens(source);
    expect(tokens.data).toBeDefined();
    // Even an empty module will have some tokens (module keyword, module name)
  });

  it("semantic tokens legend should contain expected token types", () => {
    expect(semanticTokensLegend.tokenTypes).toContain("namespace");
    expect(semanticTokensLegend.tokenTypes).toContain("type");
    expect(semanticTokensLegend.tokenTypes).toContain("typeParameter");
    expect(semanticTokensLegend.tokenTypes).toContain("function");
    expect(semanticTokensLegend.tokenTypes).toContain("variable");
    expect(semanticTokensLegend.tokenTypes).toContain("operator");
    expect(semanticTokensLegend.tokenTypes).toContain("property");
    expect(semanticTokensLegend.tokenTypes).toContain("enumMember");
    expect(semanticTokensLegend.tokenTypes).toContain("comment");
  });

  it("semantic tokens legend should contain expected modifiers", () => {
    expect(semanticTokensLegend.tokenModifiers).toContain("declaration");
    expect(semanticTokensLegend.tokenModifiers).toContain("definition");
    expect(semanticTokensLegend.tokenModifiers).toContain("readonly");
  });
});
