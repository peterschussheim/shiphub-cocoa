import AbstractComment from './AbstractComment.js'
import BBPromise from 'util/bbpromise.js'
import { keypath } from 'util/keypath.js'
import { promiseQueue } from 'util/promise-queue.js'
import IssueState from 'issue-state.js'
import { api } from 'util/api-proxy.js'
import { storeCommentDraft, clearCommentDraft, getCommentDraft } from 'util/draft-storage.js'

class Comment extends AbstractComment {
  me() { return IssueState.current.me; }
  editComment() {
    if (!IssueState.current.issue.savePending) {
      IssueState.current.editComment(this.props.commentIdx||0, this.state.code);
    }
  }
  
  issue() { return IssueState.current.issue; }
  
  isNewIssue() { return !(this.issue().number); }
  
  canClose() {
    var editingExisting = !!(this.props.comment);
    var canClose = !editingExisting && 
                   IssueState.current.issue.number > 0 &&
                   IssueState.current.issue.state === "open" &&
                   (IssueState.current.repoCanPush || IssueState.current.issueFiledByCurrentUser);
    return canClose;
  }
  
  canLock() { 
    return !this.props.comment && IssueState.current.repoCanPush && IssueState.current.issue.number > 0;
  }
  
  canEdit() {
    if (!this.props.comment) return true;
    var user = this.props.comment.user||this.props.comment.author;
    if (!user) user = ghost;
    return IssueState.current.repoCanPush || this.me().id == user.id;
  }
  
  closeButtonTitle() {
    return IssueState.current.issue.pull_request ? "Close Pull Request" : "Close Issue";
  }
  
  repoOwner() { return IssueState.current.repoOwner; }
  
  repoName() { return IssueState.current.repoName; }
    
  saveDraftState() {
    var issue = this.issue();
    var isNewIssue = this.isNewIssue();
    
    if (!isNewIssue) {
      if (this.state.editing && this.state.code.trim().length > 0) {
        storeCommentDraft(IssueState.current.repoOwner, IssueState.current.repoName, issue.number, keypath(this.props, "comment.id"), this.state.code);
      } else {
        clearCommentDraft(IssueState.current.repoOwner, IssueState.current.repoName, issue.number, keypath(this.props, "comment.id"));
      }
    }
  }
  
  restoreDraftState() {
    var issue = IssueState.current.issue;
    var isNewIssue = !(issue.number);
    
    if (!isNewIssue) {
      var draft = getCommentDraft(IssueState.current.repoOwner, IssueState.current.repoName, issue.number, keypath(this.props, "comment.id"));
      if (draft && draft.trim().length > 0) {
        this.beginEditing();
        this.updateCode(draft);
      } else if (this.state.code.length > 0) {
        if (this.props.comment && this.state.editing) {
          this.cancelEditing();
        } else {
          this.updateCode("");
        }
      }
    }
  }
  
  deleteComment() {
    IssueState.current.deleteComment(this.props.commentIdx);
  }
  
  editCommentURL() {
    var url;
    var owner = IssueState.current.repoOwner;
    var repo = IssueState.current.repoName;
    var num = IssueState.current.issue.number;
  
    if (this.props.commentIdx == 0) {
      url = `https://api.github.com/repos/${owner}/${repo}/issues/${num}`;
    } else {
      var commentIdentifier = this.props.comment.id;
      url = `https://api.github.com/repos/${owner}/${repo}/issues/comments/${commentIdentifier}`
    }
    
    return url;
  }

  editCommentQueue() {  
    var q;
    if (this.props.commentIdx == 0) {
      q = "applyPatch";
    } else {
      q = "applyCommentEdit";
    }
    return q;
  }
  
  addReaction(reaction) {
    var existing = this.findReaction(reaction);
    if (!existing) {
      IssueState.current.addReaction(this.props.commentIdx, reaction);
    }
  }
  
  toggleReaction(reaction) {
    var existing = this.findReaction(reaction);
    if (existing) {
      IssueState.current.deleteReaction(this.props.commentIdx, existing.id);
    } else {
      IssueState.current.addReaction(this.props.commentIdx, reaction);
    }
  }
  
  _save() {
    var issue = IssueState.current.issue;
    var isNewIssue = !(issue.number);
    var isAddNew = !(this.props.comment);
    var body = this.state.code;
    
    var resetState = () => {
      this.setState(Object.assign({}, this.state, {code: "", previewing: false, editing: isAddNew}));
      if (!isNewIssue) {
        clearCommentDraft(IssueState.current.repoOwner, IssueState.current.repoName, issue.number, keypath(this.props, "comment.id"));
      }
    };
    
    var rollback = (err) => {
      this.setState(Object.assign({}, this.state, {code: body, previewing: false, editing: true}));
      throw err;
    };
    
    if (isNewIssue) {
      var canSave = (issue.title || "").trim().length > 0 && !!(IssueState.current.repoOwner) && !!(IssueState.current.repoName);
      if (canSave) {
        resetState();
        IssueState.current.editComment(0, body);
        return IssueState.current.saveNewIssue().catch(rollback);
      }
    } else {
      resetState();
      if (body.trim().length > 0) {
        if (this.props.comment) {
          if (this.props.comment.body != body) {
            return IssueState.current.editComment(this.props.commentIdx, body).catch(rollback);
          }
        } else {
          return IssueState.current.addComment(body).catch(rollback);
        }
      }
    }
    
    return BBPromise.resolve();
  }
  
  saveAndClose() {
    IssueState.current.patchIssue({state: "closed"});
    this.save();
  }
  
  loginCompletions() {
    return IssueState.current.allLoginCompletions
  }
  
  needsSave() {
    var issue = IssueState.current.issue;
    var isNewIssue = !(issue.number);
    var isAddNew = !(this.props.comment);
    var body = this.state.code;
    
    if (isNewIssue) {
      var canSave = (issue.title || "").trim().length > 0 && !!(IssueState.current.repoOwner) && !!(IssueState.current.repoName);
      return canSave;
    } else {
      if (this.props.comment && !this.state.editing) {
        return false;
      }
      if (body.trim().length > 0) {
        if (this.props.comment) {
          if (this.props.comment.body != body) {
            return true;
          }
        } else {
          return true;
        }
      }
      return false;
    }
  }
  
  /* Called for task list edits that occur 
     e.g. checked a task button or reordered a task list 
  */
  onTaskListEdit(newBody) {
    if (!this.props.comment || this.state.editing) {
      this.updateCode(newBody);
    } else {
      var undo = () => {
        this.setState(Object.assign({}, this.state, {pendingEditBody: null, code: newBody, editing: true, previewing: false}));
      };
    
      this.setState(Object.assign({}, this.state, {pendingEditBody: newBody}));
      
      var owner = IssueState.current.repoOwner;
      var repo = IssueState.current.repoName;
      var num = IssueState.current.issue.number;
      var patch = { body: newBody };
      var q = this.editCommentQueue();
      var url = this.editCommentURL();
      var initialId = this.props.comment.id;
            
      promiseQueue(q, () => {
        var currentId = keypath(this.props, "comment.id") || "";
        if (currentId == initialId && newBody != this.state.pendingEditBody) {
          // let's just jump ahead to the next thing, we're already stale.
          return BBPromise.resolve();
        }
        var request = api(url, { 
          headers: { 
            Authorization: "token " + IssueState.current.token,
            'Content-Type': 'application/json',
            'Accept': 'application/json'
          }, 
          method: "PATCH",
          body: JSON.stringify(patch)
        });
        var end = () => {
          if (this.state.pendingEditBody == newBody) {
            this.setState(Object.assign({}, this.state, {pendingEditBody: null}));
          }
        };
        return new BBPromise((resolve, reject) => {
          // NB: The 1500ms delay is because GitHub only has 1s precision on updated_at
          request.then(() => {
            setTimeout(() => {
              end();
              resolve();            
            }, 1500);
          }).catch((err) => {
            setTimeout(() => {
              undo();
              reject(err);
            }, 1500);
          });
        });
      });
    }
  }
}

export default Comment;
