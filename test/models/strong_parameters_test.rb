require 'test_helper'

class StrongParamsDemoTest < ActiveSupport::TestCase
  describe 'using permit without require' do

    before do
      @hash = { 'title' => 'Test', 'body' => 'test body' }
    end

    describe 'completely unhandled params (i.e. no call to permit)' do
      before do
        @params = ActionController::Parameters.new @hash
      end
      it 'should raise error' do
        -> { Article.new @params }.must_raise ActiveModel::ForbiddenAttributesError
      end
    end

    describe 'permit some elements from params and miss others' do
      before do
        @params = ActionController::Parameters.new @hash
      end
      it 'should log non-permitted attributes' do
        ActiveSupport::Notifications.
          expects(:instrument).
          with('unpermitted_parameters.action_controller', keys: ['body']).
          once
        @params.permit(:title).must_equal 'title' => 'Test'
      end
    end

    describe 'call permit on attributes that do not exist in the model' do
      before do
        params = ActionController::Parameters.new @hash.merge('this_is_not_an_attribute_of_article' => 'test')
        @permitted_params = params.permit(:title, :this_is_not_an_attribute_of_article)
      end
      it 'ActiveRecord should raise exception on non-attribute' do
        ex = -> { Article.new @permitted_params }.must_raise ActiveRecord::UnknownAttributeError
        ex.message.must_equal 'unknown attribute: this_is_not_an_attribute_of_article'
      end
    end

    describe 'proper use of permit' do
      before do
        @params = ActionController::Parameters.new @hash
        @attributes = @params.permit(:title, :body)
      end
      it 'new - be fine when all permitted params are valid model attributes' do
        article = Article.new @attributes
        article.title.must_equal 'Test'
        article.body.must_equal 'test body'
      end
      it 'update - be fine when all permitted params are valid model attributes' do
        article = Article.first
        article.update_attributes @attributes
        article.title.must_equal 'Test'
        article.body.must_equal 'test body'
      end
    end
  end

  describe 'using the "require" method' do
    before do
      hash = {
        'article_attributes' => {'title' => 'Test', 'body' =>'test body'},
        'other_attributes' => {'amount' => '12', 'color' => 'blue' }
      }
      @params = ActionController::Parameters.new hash
    end
    describe 'require something that is not present in params' do
      it 'should raise exception' do
        ex = -> { @params.require(:category_attributes) }.must_raise ActionController::ParameterMissing
        ex.message.must_equal 'param is missing or the value is empty: category_attributes'
      end
    end
    describe 'successful require' do
      it 'should filter out everything but the required key' do
        @params.require(:article_attributes).must_equal 'title' => 'Test', 'body' =>'test body'
      end
      it 'should raise error if we try to use it as is (without permit)' do
        -> { Article.new @params.require(:article_attributes) }.must_raise ActiveModel::ForbiddenAttributesError
      end
      describe 'proper use' do
        before do
          @attributes = @params.require(:article_attributes).permit(:title, :body)
        end
        it 'new - should be fine if we use require and permit combined' do
          @article = Article.new @attributes
          @article.title.must_equal 'Test'
          @article.body.must_equal 'test body'
        end
        it 'update - should be fine if we use require and permit combined' do
          @article = Article.first
          @article.update_attributes @attributes
          @article.title.must_equal 'Test'
          @article.body.must_equal 'test body'
        end
      end
    end
  end

  describe 'nested attributes on comment (which belongs_to article)' do
    before do
      hash = {
        "comment" => {
          "author" => "John Smith",
          "content" => "Great writing!",
          "article_attributes" => {
            "title" => "Test",
            "body" => "test body",
          }
        }
      }
      @params = ActionController::Parameters.new hash
    end
    it 'shows the wrong way to permit nested params' do
      attributes = @params.
                      require(:comment).
                      permit(:author, :article_attributes)
      attributes.must_equal "author" => "John Smith"
      attributes.must_include 'author'
      attributes.wont_include 'article_attributes'
    end
    it 'shows how to permit nested params (correct way)' do
      attributes = @params.
                      require(:comment).
                      permit(:author, article_attributes: [:id, :title, :body])
      attributes.must_equal "author" => "John Smith",
                            "article_attributes" => {
                              "title" => "Test",
                              "body" => "test body"}
      comment = Comment.new attributes
      comment.author.must_equal 'John Smith'
      comment.content.must_be_nil
      comment.article.title.must_equal 'Test'
      comment.article.body.must_equal 'test body'
    end
  end

  describe 'update existing comment and existing article' do
    before do
      hash = {
        "comment" => {
          "author" => "John Smith",
          "content" => "Great writing!",
          "article_attributes" => {
            "id" => articles(:vacation).id,
            "title" => "Test",
            "body" => "test body",
          }
        }
      }
      @params = ActionController::Parameters.new hash
      @comment = comments(:thanks)
    end
    it 'shows how to permit nested params (correct way)' do
      attributes = @params.
                      require(:comment).
                      permit(:author, article_attributes: [:id, :title, :body])
      attributes.must_equal "author" => "John Smith",
                            "article_attributes" => {
                              "id" => articles(:vacation).id,
                              "title" => "Test",
                              "body" => "test body"}
      @comment.update_attributes attributes
      @comment.author.must_equal 'John Smith'
      @comment.content.must_equal comments(:thanks).content
      @comment.article.title.must_equal 'Test'
      @comment.article.body.must_equal 'test body'
    end
  end


  describe 'nested attributes on articles (which has_many comments)' do
    before do
      @hash = {
        "article" => {
          "title" => "Test",
          "body" => "test body",
          "comments_attributes" => {'0'=>{"author" => "John", "content" => "great"},
                                    '1'=>{"author" => "Mary", "content" => "awful"}}
        }
      }
      @params = ActionController::Parameters.new @hash
    end
    it 'shows the wrong way to permit nested parameters' do
      attributes = @params.
        require(:article).
        permit(:title, :comments_attributes)
      attributes.must_equal "title" => "Test"
      attributes.permit(:title, :comments_attributes).wont_include 'comments_attributes'
    end
    it 'shows how to permit nested parameters (correct way)' do
      attributes = @params.
        require(:article).
        permit(:title, comments_attributes: [:author, :content])[:comments_attributes].
          must_equal @hash['article']['comments_attributes']
    end
  end

  describe 'update existing article, update existing comment + create new comment' do
    before do
      @hash = {
        "article" => {
          "title" => "Test",
          "body" => "test body",
          "comments_attributes" => {'0'=>{"author" => "John", "content" => "great"},
                                    '1'=>{"author" => "Mary", "content" => "awful"}}
        }
      }
      @params = ActionController::Parameters.new @hash
      @article = articles(:vacation)
    end
    it 'shows how to permit nested parameters (correct way)' do
      attributes = @params.
        require(:article).
        permit(:title, comments_attributes: [:author, :content])[:comments_attributes].
          must_equal @hash['article']['comments_attributes']
    end
  end

end
